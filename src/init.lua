-- Amina S driver
-- Copyright (c) 2025 Kristian Kleiveland
-- Licensed under the MIT License.

-- SmartThings Zigbee driver for Amina S EV charger
-- Capabilities: switch, switchLevel, currentMeasurement, powerMeter, voltageMeasurement, presenceSensor, refresh

local zigbee_driver  = require "st.zigbee"
local capabilities   = require "st.capabilities"
local zcl_clusters   = require "st.zigbee.zcl.clusters"
local data_types     = require "st.zigbee.data_types"

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
  return clamp(math.floor(((amps - MIN_AMPS) / range) * 100), 0, 100)
end

------------------------------------------------------------
-- Core functions
------------------------------------------------------------

-- Update local state and emit currentMeasurement immediately
-- SwitchLevel is updated only when the device reports back
local function update_persistence_and_current(device, amps_in)
  local max_limit = (device.preferences and device.preferences.maxCurrent) or MAX_AMPS
  local amps = clamp(amps_in, MIN_AMPS, max_limit)
  device:set_field("last_set_amps", amps, { persist = true })
  device:emit_event(capabilities.currentMeasurement.current(amps))
end

-- Send Level Control command to the charger
local function send_level_command(device, amps)
  update_persistence_and_current(device, amps)
  local cmd = zcl_clusters.Level.server.commands.MoveToLevelWithOnOff(
    device, data_types.Uint8(amps), data_types.Uint16(0)
  ):to_endpoint(EP)
  device:send(cmd)
end

------------------------------------------------------------
-- Capability handlers
------------------------------------------------------------

-- Handle slider input (switchLevel.setLevel)
local function handle_set_level(_, device, command)
  local percent   = tonumber(command.args.level) or 0
  local max_limit = (device.preferences and device.preferences.maxCurrent) or MAX_AMPS
  local range     = math.max(1, (max_limit - MIN_AMPS))
  local raw_amps  = MIN_AMPS + (percent / 100) * range
  local amps      = clamp(math.floor(raw_amps + 0.5), MIN_AMPS, max_limit)
  send_level_command(device, amps)
end

-- Handle switch ON: restore last amps or fallback to maxCurrent
local function handle_switch_on(_, device, _)
  device:send(zcl_clusters.OnOff.commands.On(device):to_endpoint(EP))
  local fallback  = (device.preferences and device.preferences.maxCurrent) or MAX_AMPS
  local last_amps = device:get_field("last_set_amps") or fallback
  send_level_command(device, clamp(last_amps, MIN_AMPS, fallback))
end

-- Handle switch OFF
local function handle_switch_off(_, device, _)
  device:send(zcl_clusters.OnOff.commands.Off(device):to_endpoint(EP))
  device:emit_event(capabilities.switch.switch.off())
end

-- Manual refresh: read ActivePower, CurrentLevel, RMSVoltage
local function handle_refresh(_, device, _)
  device:send(zcl_clusters.ElectricalMeasurement.attributes.ActivePower:read(device):to_endpoint(EP))
  device:send(zcl_clusters.Level.attributes.CurrentLevel:read(device):to_endpoint(EP))
  device:send(zcl_clusters.ElectricalMeasurement.attributes.RMSVoltage:read(device):to_endpoint(EP))
end

------------------------------------------------------------
-- Preference handler
------------------------------------------------------------

-- Handle changes to preferences (e.g. maxCurrent)
local function handle_info_changed(device, args)
  local old_prefs = (args and args.old_st_store and args.old_st_store.preferences) or {}
  local old       = old_prefs.maxCurrent
  local new_curr  = (device.preferences and device.preferences.maxCurrent) or MAX_AMPS
  if old ~= nil and old ~= new_curr then
    -- Preference changed; no automatic action
  end
end

------------------------------------------------------------
-- Zigbee attribute handlers
------------------------------------------------------------

-- Handle ActivePower reports (W)
local function handle_active_power(_, device, value)
  local watts = value and value.value
  if type(watts) == "number" then
    device:emit_event(capabilities.powerMeter.power(watts))
    local present = (watts > 10) and "present" or "not_present"
    device:emit_event(capabilities.presenceSensor.presence[present]())
  end
end

-- Handle RMSVoltage reports (V)
local function handle_rms_voltage(_, device, value)
  local volts = value and value.value
  if type(volts) == "number" then
    device:emit_event(capabilities.voltageMeasurement.voltage(volts))
  end
end

-- Handle CurrentLevel reports (amps)
-- This is the authoritative update for the slider
local function handle_current_level(_, device, value)
  local amps      = tonumber(value and value.value) or MIN_AMPS
  local max_limit = (device.preferences and device.preferences.maxCurrent) or MAX_AMPS
  update_persistence_and_current(device, amps)
  local percent = amps_to_percent(amps, max_limit)
  device:emit_event(capabilities.switchLevel.level(percent))
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
