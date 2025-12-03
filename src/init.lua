-- Amina S driver
-- Copyright (c) 2025 Kristian Kleiveland
-- Licensed under the MIT License.

-- English documentation:
-- This SmartThings Edge Zigbee driver provides robust control and telemetry for the Amina S EV charger.
-- It manually constructs Zigbee ZCL commands to read proprietary attributes from the custom Amina cluster (0xFEE7),
-- marking requests as manufacturer-specific using the Amina manufacturer code (0x143B). The driver decodes alarm and
-- EV status bitmaps into readable notifications visible in the app’s History. Standard clusters are used for on/off,
-- level (amps via percentage), voltage, current, active power, and total energy. All custom reads are wrapped in pcall
-- to avoid crashes if the device rejects or fails a request.

local capabilities   = require "st.capabilities"
local zigbee_driver  = require "st.zigbee"
local clusters       = require "st.zigbee.zcl.clusters"
local cluster_base   = require "st.zigbee.cluster_base"
local data_types     = require "st.zigbee.data_types"
local zcl_global     = require "st.zigbee.zcl.global_commands"
local log            = require "log"

-- Endpoint and Amina custom cluster constants
local EP = 10
local AMINA_CLUSTER_ID = 0xFEE7
local AMINA_MFG_CODE   = 0x143B

-- Amina custom attribute IDs
local AMINA = {
  TotalActiveEnergy  = { ID = 0x0010 }, -- Wh (convert to kWh)
  LastSessionEnergy  = { ID = 0x0011 }, -- Wh (convert to kWh)
  Alarms             = { ID = 0x0002 }, -- Bitmap16
  EVStatuses         = { ID = 0x0003 }, -- Bitmap16
  ConnectStatuses    = { ID = 0x0004 }, -- Bitmap16
}

-- Human-readable alarm texts mapped to bit positions
local ALARM_TEXTS = {
  [0]  = "Welded Relay",
  [1]  = "Wrong Voltage Balance",
  [2]  = "DC Leakage",
  [3]  = "AC Leakage",
  [4]  = "Temperature Error",
  [5]  = "Overvoltage",
  [6]  = "Undervoltage",
  [7]  = "Overcurrent",
  [8]  = "Car Communication Error",
  [9]  = "Charger Processing Error",
  [10] = "Critical Overcurrent",
  [11] = "Critical Power Loss",
}

-- EV status texts mapped to bit positions
local EV_STATUS_TEXTS = {
  [0]  = "EV Connected",
  [1]  = "Relays Active",
  [2]  = "Power Delivered",
  [3]  = "Paused Charging",
  [4]  = "EV Ready",
  [15] = "Derating (High Temp)",
}

-- Percent level to amps conversion (for logs)
local MIN_AMP = 6
local MAX_AMP = 32
local function level_to_amps(level)
  local pct = math.max(0, math.min(100, level or 0))
  return MIN_AMP + (MAX_AMP - MIN_AMP) * (pct / 100)
end

-- Decode bitmaps into text using Lua 5.3 bitwise operations
local function decode_bitmap(value, text_map)
  local status_list = {}
  local val = value or 0
  for bit_pos, text in pairs(text_map) do
    if (val & (1 << bit_pos)) ~= 0 then
      table.insert(status_list, text)
    end
  end
  return table.concat(status_list, ", ")
end

-- Manual ZCL ReadAttribute to Amina custom cluster with manufacturer header
local function read_amina(device, attr_def)
  local status, err = pcall(function()
    local read_cmd = zcl_global.ReadAttribute({ attr_def.ID })
    local msg = read_cmd:to_cluster(AMINA_CLUSTER_ID):to_endpoint(EP)
    msg.body.zcl_header.mfg_code = data_types.Uint16(AMINA_MFG_CODE)
    msg.body.zcl_header.frame_ctrl:set_mfg_specific()
    device:send(msg)
    return "OK"
  end)
  if status and err == "OK" then
    log.info(string.format("FEE7: Sent ReadAttr 0x%04X (mfg 0x%04X) OK", attr_def.ID, AMINA_MFG_CODE))
  else
    log.error(string.format("FEE7: Manual build failed for 0x%04X: %s", attr_def.ID, tostring(err)))
  end
end

-- Command handlers

local function handle_switch_cmd(_, device, command)
  if command.command == capabilities.switch.commands.on.NAME then
    device:send(clusters.OnOff.commands.On(device):to_endpoint(EP))
    device:emit_event(capabilities.switch.switch.on())
  elseif command.command == capabilities.switch.commands.off.NAME then
    device:send(clusters.OnOff.commands.Off(device):to_endpoint(EP))
    device:emit_event(capabilities.switch.switch.off())
  end
end

local function handle_set_level(_, device, command)
  local level = command.args.level or 0
  local amps = level_to_amps(level)
  local zcl_level = math.floor((level / 100) * 255 + 0.5)
  device:send(clusters.Level.commands.MoveToLevelWithOnOff(device, zcl_level, 0):to_endpoint(EP))
  device:emit_event(capabilities.switchLevel.level(level))
  log.info(string.format("Set level %d%% (~%.1f A), ZCL=%d", level, amps, zcl_level))
end

local function handle_refresh(_, device)
  log.info(">>> REFRESH START <<<")
  -- Standard clusters
  device:send(clusters.OnOff.attributes.OnOff:read(device):to_endpoint(EP))
  device:send(clusters.Level.attributes.CurrentLevel:read(device):to_endpoint(EP))
  device:send(clusters.ElectricalMeasurement.attributes.RMSVoltage:read(device):to_endpoint(EP))
  device:send(clusters.ElectricalMeasurement.attributes.RMSCurrent:read(device):to_endpoint(EP))
  device:send(clusters.ElectricalMeasurement.attributes.ActivePower:read(device):to_endpoint(EP))
  -- Amina custom cluster (manual reads)
  read_amina(device, AMINA.TotalActiveEnergy)
  read_amina(device, AMINA.LastSessionEnergy)
  read_amina(device, AMINA.Alarms)
  read_amina(device, AMINA.EVStatuses)
  read_amina(device, AMINA.ConnectStatuses)
  log.info(">>> REFRESH END <<<")
end

local function do_configure(device)
  device:send(clusters.OnOff.attributes.OnOff:configure_reporting(device, 0, 3600, 1):to_endpoint(EP))
  device:send(clusters.Level.attributes.CurrentLevel:configure_reporting(device, 0, 3600, 1):to_endpoint(EP))
  device:send(clusters.ElectricalMeasurement.attributes.RMSVoltage:configure_reporting(device, 1, 600, 1):to_endpoint(EP))
  device:send(clusters.ElectricalMeasurement.attributes.RMSCurrent:configure_reporting(device, 1, 600, 1):to_endpoint(EP))
  device:send(clusters.ElectricalMeasurement.attributes.ActivePower:configure_reporting(device, 1, 600, 1):to_endpoint(EP))
end

-- Attribute handlers (standard clusters)

local function onoff_attr_handler(_, device, value)
  device:emit_event(value.value and capabilities.switch.switch.on() or capabilities.switch.switch.off())
end

local function level_attr_handler(_, device, value)
  local zcl_level = value.value or 0
  local st_level = math.floor((zcl_level / 255) * 100 + 0.5)
  device:emit_event(capabilities.switchLevel.level(st_level))
end

local function voltage_attr_handler(_, device, value)
  device:emit_event(capabilities.voltageMeasurement.voltage(value.value or 0))
end

local function current_attr_handler(_, device, value)
  local amps = (value.value or 0) / 1000.0
  device:emit_event(capabilities.currentMeasurement.current(amps))
end

local function power_attr_handler(_, device, value)
  device:emit_event(capabilities.powerMeter.power(value.value or 0))
end

-- Attribute handlers (Amina FEE7)

local function energy_total_attr_handler(_, device, value)
  local kwh = (value.value or 0) / 1000.0
  device:emit_event(capabilities.energyMeter.energy(kwh))
end

local function energy_session_attr_handler(_, device, value)
  local kwh = (value.value or 0) / 1000.0
  -- Emit as notification to ensure visibility without extra profile components
  device:emit_event(capabilities.notification.notification({ value = string.format("Last Session: %.2f kWh", kwh) }))
end

local function alarms_attr_handler(_, device, value)
  local raw_val = value.value or 0
  if raw_val > 0 then
    local msg = decode_bitmap(raw_val, ALARM_TEXTS)
    log.warn("FEE7 ALARM: " .. msg)
    device:emit_event(capabilities.notification.notification({ value = "Alarm: " .. msg }))
  else
    log.info("FEE7: No Alarms")
  end
end

local function ev_statuses_attr_handler(_, device, value)
  local raw_val = value.value or 0
  local msg = decode_bitmap(raw_val, EV_STATUS_TEXTS)
  if msg == "" then msg = "Idle / Disconnected" end
  log.info("FEE7 EV Status: " .. msg)
  device:emit_event(capabilities.notification.notification({ value = "EV Status: " .. msg }))
end

local function connect_statuses_attr_handler(_, device, value)
  local raw_val = value.value or 0
  local msg = (raw_val == 1) and "Cable Connected" or "Cable Disconnected"
  log.info("FEE7 Connect Status: " .. msg)
  device:emit_event(capabilities.notification.notification({ value = msg }))
end

-- Driver definition

local driver = zigbee_driver("amina-s-driver", {
  supported_capabilities = {
    capabilities.switch,
    capabilities.refresh,
    capabilities.switchLevel,
    capabilities.voltageMeasurement,
    capabilities.currentMeasurement,
    capabilities.powerMeter,
    capabilities.energyMeter,
    capabilities.notification,
  },
  capability_handlers = {
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME]  = handle_switch_cmd,
      [capabilities.switch.commands.off.NAME] = handle_switch_cmd,
    },
    [capabilities.refresh.ID] = {
      [capabilities.refresh.commands.refresh.NAME] = handle_refresh,
    },
    [capabilities.switchLevel.ID] = {
      [capabilities.switchLevel.commands.setLevel.NAME] = handle_set_level,
    },
  },
  lifecycle_handlers = {
    doConfigure = do_configure,
  },
  zigbee_handlers = {
    attr = {
      [clusters.OnOff.ID] = {
        [clusters.OnOff.attributes.OnOff.ID] = onoff_attr_handler,
      },
      [clusters.Level.ID] = {
        [clusters.Level.attributes.CurrentLevel.ID] = level_attr_handler,
      },
      [clusters.ElectricalMeasurement.ID] = {
        [clusters.ElectricalMeasurement.attributes.RMSVoltage.ID]  = voltage_attr_handler,
        [clusters.ElectricalMeasurement.attributes.RMSCurrent.ID]  = current_attr_handler,
        [clusters.ElectricalMeasurement.attributes.ActivePower.ID] = power_attr_handler,
      },
      [AMINA_CLUSTER_ID] = {
        [AMINA.TotalActiveEnergy.ID] = energy_total_attr_handler,
        [AMINA.LastSessionEnergy.ID] = energy_session_attr_handler,
        [AMINA.Alarms.ID]            = alarms_attr_handler,
        [AMINA.EVStatuses.ID]        = ev_statuses_attr_handler,
        [AMINA.ConnectStatuses.ID]   = connect_statuses_attr_handler,
      },
    },
  },
})

driver:run()
