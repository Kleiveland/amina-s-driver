-- Amina S driver
-- Copyright (c) 2025 Kristian Kleiveland
-- Licensed under the MIT License.

local zigbee_driver  = require "st.zigbee"
local capabilities   = require "st.capabilities"
local zcl_clusters   = require "st.zigbee.zcl.clusters"
local data_types     = require "st.zigbee.data_types"
local log            = require "log"

------------------------------------------------------------
-- Constants
------------------------------------------------------------
local EP                   = 10 -- Charger endpoint
local CLUSTER_LEVEL        = 0x0008
local CLUSTER_ONOFF        = 0x0006
local CLUSTER_ELEC         = 0x0B04
local ATTR_ACTIVE_POWER    = 0x050B
local ATTR_RMS_VOLTAGE     = 0x0505
local MIN_AMPS             = 6
local MAX_AMPS             = 32

------------------------------------------------------------
-- Helper functions
------------------------------------------------------------

-- Clamp a number between min and max
local function clamp(n, min, max) return math.max(min, math.min(n, max)) end

-- Convert amps to slider percent based on maxCurrent preference
local function amps_to_percent(amps, max_limit)
  local range = math.max(1, (max_limit - MIN_AMPS))
  return clamp(math.floor(((amps - MIN_AMPS) / range) * 100 + 0.5), 0, 100)
end

-- Convert slider percent to amps based on maxCurrent preference
local function percent_to_amps(percent, max_limit)
  local range = math.max(1, (max_limit - MIN_AMPS))
  local raw_amps = MIN_AMPS + (clamp(percent, 0, 100) / 100) * range
  return clamp(math.floor(raw_amps + 0.5), MIN_AMPS, max_limit)
end

-- Safe wrapper to prevent hard failures in handlers
local function safe_exec(name, func)
  local ok, err = pcall(func)
  if not ok then
    log.error(string.format("[CRITICAL] Error in '%s': %s", name, tostring(err)))
  end
end

------------------------------------------------------------
-- Core functions
------------------------------------------------------------

-- V14: Optimistically updates BOTH UI and local persistence
local function update_ui_and_persistence(device, amps_in)
  safe_exec("update_ui_and_persistence", function()
    local max_limit = (device.preferences and device.preferences.maxCurrent) or MAX_AMPS
    local amps = clamp(amps_in, MIN_AMPS, max_limit)

    -- Store the REQUESTED value for restoration
    device:set_field("last_set_amps", amps, { persist = true })

    -- Optimistic UI update for currentMeasurement (e.g., 17 A)
    device:emit_event(capabilities.currentMeasurement.current(amps))

    -- Optimistic UI update for switchLevel (e.g., 44%)
    local percent = amps_to_percent(amps, max_limit)
    device:emit_event(capabilities.switchLevel.level(percent))

    log.info(string.format("OPTIMISTIC UI: Showing %d A / %d%% immediately.", amps, percent))
  end)
end

-- Send Level Control command to the charger
local function send_level_command(device, amps)
  safe_exec("send_level_command", function()
    local max_limit = (device.preferences and device.preferences.maxCurrent) or MAX_AMPS
    local setpoint = clamp(amps, MIN_AMPS, max_limit)

    -- STEP 1: Optimistic UI update (prevents spinning)
    update_ui_and_persistence(device, setpoint)

    -- STEP 2: Send ZCL Level command (Amina interprets Uint8 as amps)
    local cmd = zcl_clusters.Level.server.commands.MoveToLevelWithOnOff(
      device, data_types.Uint8(setpoint), data_types.Uint16(0)
    ):to_endpoint(EP)
    device:send(cmd)

    log.info(string.format("Sent Level command: %d A. Requesting immediate Level read for correction.", setpoint))

    -- STEP 3: FORCE IMMEDIATE FEEDBACK for fast correction (e.g., capped 10 A)
    device:send(zcl_clusters.Level.attributes.CurrentLevel:read(device):to_endpoint(EP))
  end)
end

------------------------------------------------------------
-- Capability handlers
------------------------------------------------------------

-- Handle slider input (switchLevel.setLevel)
local function handle_set_level(_, device, command)
  safe_exec("handle_set_level", function()
    local percent = tonumber(command.args.level) or 0
    local max_limit = (device.preferences and device.preferences.maxCurrent) or MAX_AMPS
    local amps = percent_to_amps(percent, max_limit)
    send_level_command(device, amps)
  end)
end

-- Handle switch ON: restore last amps or fallback to maxCurrent
local function handle_switch_on(_, device, _)
  safe_exec("handle_switch_on", function()
    device:send(zcl_clusters.OnOff.commands.On(device):to_endpoint(EP))
    local max_limit = (device.preferences and device.preferences.maxCurrent) or MAX_AMPS
    local last_amps = device:get_field("last_set_amps") or max_limit
    send_level_command(device, clamp(last_amps, MIN_AMPS, max_limit))
  end)
end

-- Handle switch OFF
local function handle_switch_off(_, device, _)
  safe_exec("handle_switch_off", function()
    device:send(zcl_clusters.OnOff.commands.Off(device):to_endpoint(EP))
    device:emit_event(capabilities.switch.switch.off())
  end)
end

-- Manual refresh: read ActivePower, CurrentLevel, RMSVoltage
local function handle_refresh(_, device, _)
  safe_exec("handle_refresh", function()
    log.info("Performing manual Refresh...")
    device:send(zcl_clusters.ElectricalMeasurement.attributes.ActivePower:read(device):to_endpoint(EP))
    device:send(zcl_clusters.Level.attributes.CurrentLevel:read(device):to_endpoint(EP))
    device:send(zcl_clusters.ElectricalMeasurement.attributes.RMSVoltage:read(device):to_endpoint(EP))
  end)
end

------------------------------------------------------------
-- Preference handler
------------------------------------------------------------

-- Handle changes to preferences (e.g., maxCurrent)
local function handle_info_changed(device, args)
  safe_exec("handle_info_changed", function()
    -- No automatic action. New maxCurrent applies on next command/report.
  end)
end

------------------------------------------------------------
-- Zigbee attribute handlers
------------------------------------------------------------

-- Handle ActivePower reports (W)
local function handle_active_power(_, device, value)
  safe_exec("handle_active_power", function()
    local watts = value and value.value
    if type(watts) == "number" then
      device:emit_event(capabilities.powerMeter.power(watts))
      local present = (watts > 10) and "present" or "not_present"
      device:emit_event(capabilities.presenceSensor.presence[present]())
    end
  end)
end

-- Handle RMSVoltage reports (V)
local function handle_rms_voltage(_, device, value)
  safe_exec("handle_rms_voltage", function()
    local volts = value and value.value
    if type(volts) == "number" then
      device:emit_event(capabilities.voltageMeasurement.voltage(volts))
    end
  end)
end

-- Handle CurrentLevel reports (amps from charger)
-- Authoritative UI update: corrects optimistic value to the confirmed device state.
local function handle_current_level(_, device, value)
  safe_exec("handle_current_level", function()
    local max_limit = (device.preferences and device.preferences.maxCurrent) or MAX_AMPS
    local amps = tonumber(value and value.value) or MIN_AMPS
    amps = clamp(amps, MIN_AMPS, max_limit)

    -- Persist confirmed value
    device:set_field("last_set_amps", amps, { persist = true })

    -- Emit BOTH currentMeasurement and switchLevel based on confirmed amps
    device:emit_event(capabilities.currentMeasurement.current(amps))
    local percent = amps_to_percent(amps, max_limit)
    device:emit_event(capabilities.switchLevel.level(percent))

    log.info(string.format("AUTHORITATIVE UI: Received confirmed Level: %d A. Corrected UI to %d%%.", amps, percent))
  end)
end

------------------------------------------------------------
-- Driver template
------------------------------------------------------------

local driver_template = {
  supported_capabilities = {
    capabilities.switch,
    capabilities.switchLevel,
    capabilities.currentMeasurement,
    capabilities.powerMeter,
    capabilities.voltageMeasurement,
    capabilities.presenceSensor,
    capabilities.refresh,
  },
  lifecycle_handlers = {
    init        = function(d, dev) handle_refresh(d, dev) end,
    added       = function(d, dev) handle_refresh(d, dev) end,
    doConfigure = function(d, dev) handle_refresh(d, dev) end,
    infoChanged = handle_info_changed,
  },
  capability_handlers = {
    [capabilities.switchLevel.ID] = {
      [capabilities.switchLevel.commands.setLevel.NAME] = handle_set_level,
    },
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME]  = handle_switch_on,
      [capabilities.switch.commands.off.NAME] = handle_switch_off,
    },
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = handle_refresh,
    },
  },
  zigbee_handlers = {
    attr = {
      [CLUSTER_ELEC] = {
        [ATTR_ACTIVE_POWER] = handle_active_power,
        [ATTR_RMS_VOLTAGE]  = handle_rms_voltage,
      },
      [CLUSTER_LEVEL] = {
        [zcl_clusters.Level.attributes.CurrentLevel.ID] = handle_current_level,
      },
      [CLUSTER_ONOFF] = {
        [zcl_clusters.OnOff.attributes.OnOff.ID] = function(_, device, value)
          local on = (value and (value.value == true or tonumber(value.value) == 1)) or false
          device:emit_event(capabilities.switch.switch[on and "on" or "off"]())
        end
      }
    }
  }
}

zigbee_driver("amina_s_ev_driver", driver_template):run()
