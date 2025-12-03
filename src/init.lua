-- Amina S driver
-- Copyright (c) 2025 Kristian Kleiveland
-- Licensed under the MIT License.

-- Amina S EV Charger Zigbee Edge Driver
-- Provides full control and status reading via custom ZCL messaging and standard clusters.

local capabilities   = require "st.capabilities"
local zigbee_driver  = require "st.zigbee"
local clusters       = require "st.zigbee.zcl.clusters"
local data_types     = require "st.zigbee.data_types"
local zcl_global     = require "st.zigbee.zcl.global_commands"
local log            = require "log"

-- Device specific constants
local EP = 10
local AMINA_CLUSTER_ID = 0xFEE7
local AMINA_MFG_CODE   = 0x143B

-- Amina proprietary cluster attribute IDs
local AMINA = {
  TotalActiveEnergy  = { ID = 0x0010 },
  LastSessionEnergy  = { ID = 0x0011 },
  Alarms             = { ID = 0x0002 },
  EVStatuses         = { ID = 0x0003 },
  ConnectStatuses    = { ID = 0x0004 },
}

-- Decoding maps for custom status values (Bitmaps)
local ALARM_TEXTS = {
  [0]  = "Welded Relay", [1]  = "Wrong Voltage Balance", [2]  = "DC Leakage",
  [3]  = "AC Leakage", [4]  = "Temperature Error", [5]  = "Overvoltage",
  [6]  = "Undervoltage", [7]  = "Overcurrent", [8]  = "Car Communication Error",
  [9]  = "Charger Processing Error", [10] = "Critical Overcurrent", [11] = "Critical Power Loss",
}

local EV_STATUS_TEXTS = {
  [0]  = "EV Connected", [1]  = "Relays Active", [2]  = "Power Delivered",
  [3]  = "Paused Charging", [4]  = "EV Ready", [15] = "Derating (High Temp)",
}

local CONNECT_STATUS_TEXTS = {
  [0] = "WiFi Connected", [4] = "Zigbee Connected", [14] = "Auth Waiting", [15] = "Auth Approved",
}

local MIN_AMP = 6
local MAX_AMP = 32

-- Helper to convert the 0-100% dimmer level to the actual Ampere range (6A-32A)
local function level_to_amps(level)
  local pct = math.max(0, math.min(100, level or 0))
  return MIN_AMP + (MAX_AMP - MIN_AMP) * (pct / 100)
end

-- Bitwise decoding helper function to translate raw bitmaps into a human-readable list
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

-- Function to manually construct and send ZCL read requests for proprietary attributes
-- This custom frame ensures communication with the manufacturer-specific cluster 0xFEE7
local function read_amina(device, attr_def)
  local status, err = pcall(function()
    local read_cmd = zcl_global.ReadAttribute({ attr_def.ID })
    local msg = read_cmd:to_cluster(AMINA_CLUSTER_ID):to_endpoint(EP)

    -- Inject manufacturer specific flag and code into the ZCL header
    msg.body.zcl_header.mfg_code = data_types.Uint16(AMINA_MFG_CODE)
    msg.body.zcl_header.frame_ctrl:set_mfg_specific()

    device:send(msg)
    return "OK"
  end)

  if status and err == "OK" then
    log.info(string.format("FEE7: Sent ReadAttr 0x%04X OK", attr_def.ID))
  else
    log.error(string.format("FEE7: Manual ZCL read failed for 0x%04X: %s", attr_def.ID, tostring(err)))
    -- Send notification to the app history on failure
    device:emit_event(capabilities.notification.notification({ value = string.format("ERROR: Amina read failed for 0x%04X", attr_def.ID) }))
  end
end

-- Device command handlers
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
  -- Convert 0-100 scale to ZCL 0-255 scale
  local zcl_level = math.floor((level / 100) * 255 + 0.5)
  local amps = level_to_amps(level)

  -- MoveToLevelWithOnOff command is used to set the current limit
  device:send(clusters.Level.commands.MoveToLevelWithOnOff(device, zcl_level, 0):to_endpoint(EP))
  device:emit_event(capabilities.switchLevel.level(level))
  log.info(string.format("Set level %d%% (~%.1f A), ZCL=%d", level, amps, zcl_level))
end

local function handle_refresh(_, device)
  -- Read standard attributes
  device:send(clusters.OnOff.attributes.OnOff:read(device):to_endpoint(EP))
  device:send(clusters.Level.attributes.CurrentLevel:read(device):to_endpoint(EP))
  device:send(clusters.ElectricalMeasurement.attributes.ActivePower:read(device):to_endpoint(EP))
  
  -- Read additional metering data (Extended Refresh)
  device:send(clusters.ElectricalMeasurement.attributes.RMSVoltage:read(device):to_endpoint(EP))
  device:send(clusters.ElectricalMeasurement.attributes.RMSCurrent:read(device):to_endpoint(EP))
  
  -- Trigger read for proprietary attributes (0xFEE7)
  read_amina(device, AMINA.TotalActiveEnergy)
  read_amina(device, AMINA.LastSessionEnergy)
  read_amina(device, AMINA.Alarms)
  read_amina(device, AMINA.EVStatuses)
  read_amina(device, AMINA.ConnectStatuses)
end

local function do_configure(device)
  -- Configure attribute reporting for standard clusters
  device:send(clusters.OnOff.attributes.OnOff:configure_reporting(device, 0, 3600, 1):to_endpoint(EP))
  device:send(clusters.Level.attributes.CurrentLevel:configure_reporting(device, 0, 3600, 1):to_endpoint(EP))
  device:send(clusters.ElectricalMeasurement.attributes.RMSVoltage:configure_reporting(device, 1, 600, 1):to_endpoint(EP))
  device:send(clusters.ElectricalMeasurement.attributes.RMSCurrent:configure_reporting(device, 1, 600, 1):to_endpoint(EP))
  device:send(clusters.ElectricalMeasurement.attributes.ActivePower:configure_reporting(device, 1, 600, 1):to_endpoint(EP))
end

-- Standard attribute handlers
local function onoff_attr_handler(_, device, value)
  device:emit_event(value.value and capabilities.switch.switch.on() or capabilities.switch.switch.off())
end

local function level_attr_handler(_, device, value)
  local zcl_level = value.value or 0
  local st_level = math.floor((zcl_level / 255) * 100 + 0.5)
  device:emit_event(capabilities.switchLevel.level(st_level))
end

local function power_attr_handler(_, device, value)
  device:emit_event(capabilities.powerMeter.power(value.value or 0))
end

local function voltage_attr_handler(_, device, value)
  device:emit_event(capabilities.voltageMeasurement.voltage(value.value or 0))
end

local function current_attr_handler(_, device, value)
  local amps = (value.value or 0) / 1000.0
  device:emit_event(capabilities.currentMeasurement.current(amps))
end

local function energy_total_attr_handler(_, device, value)
  -- Convert Watt-hours (Wh) to Kilowatt-hours (kWh)
  local kwh = (value.value or 0) / 1000.0
  device:emit_event(capabilities.energyMeter.energy(kwh))
end

local function energy_session_attr_handler(_, device, value)
  -- Convert Wh to kWh and output as a notification
  local kwh = (value.value or 0) / 1000.0
  device:emit_event(capabilities.notification.notification({ value = string.format("Last Session: %.2f kWh", kwh) }))
end

-- Handlers for the proprietary 0xFEE7 cluster

local function alarms_attr_handler(_, device, value)
  local raw_val = value.value or 0
  
  -- Map any active alarm to the Tamper Alert capability
  if raw_val > 0 then
    device:emit_event(capabilities.tamperAlert.tamper.detected())
    local msg = decode_bitmap(raw_val, ALARM_TEXTS)
    device:emit_event(capabilities.notification.notification({ value = "Alarm: " .. msg }))
  else
    device:emit_event(capabilities.tamperAlert.tamper.clear())
  end
end

local function ev_statuses_attr_handler(_, device, value)
  local raw_val = value.value or 0
  local msg = decode_bitmap(raw_val, EV_STATUS_TEXTS)
  if msg == "" then msg = "Idle / Disconnected" end

  -- Map EV Connected status (Bit 0) to a Contact Sensor
  if (raw_val & 1) ~= 0 then
    device:emit_event(capabilities.contactSensor.contact.closed()) 
  else
    device:emit_event(capabilities.contactSensor.contact.open())   
  end
  
  -- Map Power delivered status (Bit 2) to a Motion Sensor
  if (raw_val & (1 << 2)) ~= 0 then
    device:emit_event(capabilities.motionSensor.motion.active()) 
  else
    device:emit_event(capabilities.motionSensor.motion.inactive())
  end

  -- Map EV ready status (Bit 4) to a Presence Sensor
  if (raw_val & (1 << 4)) ~= 0 then
    device:emit_event(capabilities.presenceSensor.presence.present()) 
  else
    device:emit_event(capabilities.presenceSensor.presence.not_present())
  end

  -- Map Derating (high temp) status (Bit 15) to a Temperature Alarm
  if (raw_val & (1 << 15)) ~= 0 then
    device:emit_event(capabilities.temperatureAlarm.heatAlarm.heat())
  else
    device:emit_event(capabilities.temperatureAlarm.heatAlarm.cleared())
  end

  -- Send full status list as a notification (includes bits 1 and 3)
  device:emit_event(capabilities.notification.notification({ value = "EV Status: " .. msg }))
end

local function connect_statuses_attr_handler(_, device, value)
  local raw_val = value.value or 0
  -- Log network status for diagnostic purposes
  local msg = decode_bitmap(raw_val, CONNECT_STATUS_TEXTS)
  log.info("FEE7 Network Status: " .. msg)
end

-- Driver definition
local driver = zigbee_driver("amina-s-driver", {
  supported_capabilities = {
    capabilities.switch, capabilities.refresh, capabilities.switchLevel, 
    capabilities.voltageMeasurement, capabilities.currentMeasurement, 
    capabilities.powerMeter, capabilities.energyMeter, 
    capabilities.notification,
    -- Enhanced Automation Capabilities
    capabilities.contactSensor, capabilities.tamperAlert, capabilities.temperatureAlarm,
    capabilities.motionSensor, capabilities.presenceSensor,
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
    }
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
        [clusters.ElectricalMeasurement.attributes.ActivePower.ID] = power_attr_handler,
        [clusters.ElectricalMeasurement.attributes.RMSVoltage.ID] = voltage_attr_handler,
        [clusters.ElectricalMeasurement.attributes.RMSCurrent.ID] = current_attr_handler,
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
