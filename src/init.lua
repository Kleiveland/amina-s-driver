-- Amina S driver
-- Copyright (c) 2025 Kristian Kleiveland
-- Licensed under the MIT License.
--
-- Logic based on Amina documentation and verified against Zigbee2MQTT standards.

local capabilities = require "st.capabilities"
local zigbee_driver = require "st.zigbee"
local defaults = require "st.zigbee.defaults"
local clusters = require "st.zigbee.clusters"
local log = require "log"

-- --- ZIGBEE CLUSTER DEFINITIONS ---
local ZCL_ON_OFF_CLUSTER = clusters.OnOff.ID
local ZCL_LEVEL_CONTROL_CLUSTER = clusters.LevelControl.ID
local ZCL_ELECTRICAL_MEASUREMENT_CLUSTER = clusters.ElectricalMeasurement.ID
local AMINA_S_CONTROL_CLUSTER = 0xFEE7  -- Amina Custom Cluster ID for Energy/Alarms
local AMINA_ENERGY_ATTRIBUTE = 0x0010  -- Total Active Energy (Wh) Attribute
local AMINA_ALARMS_ATTRIBUTE = 0x0002  -- Alarms (map16) Attribute
local AMINA_STATUSES_ATTRIBUTE = 0x0003 -- EV Statuses (map16) Attribute

local CHARGER_ENDPOINT = 10 
local scaling_factors = {}

-- --- ALARM MAPPING (BASED ON AMINA DOCUMENTATION) ---
local ALARM_MESSAGES = {
  [0] = "Critical: Welded relay(s) detected. Requires professional service.",
  [1] = "Safety: Wrong voltage balance detected. Check installation.",
  [2] = "Safety: RDC-DD DC leakage detected. Disconnect and reconnect car.",
  [3] = "Safety: RDC-DD AC leakage detected (>30mA). Disconnect and reconnect car.",
  [4] = "Safety: Temperature error (drastic increase around connector). Check installation.",
  [5] = "Warning: Overvoltage alarm (>245V). Charging switched off.",
  [6] = "Warning: Undervoltage alarm (<200V). Charging switched off.",
  [7] = "Warning: Overcurrent alarm (>10% allowed current). Charging switched off.",
  [8] = "Warning: Car communication error. Disconnect car to reset.",
  [9] = "Warning: Charger processing error (Watchdog triggered). Requires acknowledgement.",
  [10] = "Safety: Critical overcurrent alarm (>60A). Charging switched off.",
  [11] = "Warning: Critical powerloss alarm.",
}

-- --- EV STATUS MAPPING (BASED ON AMINA DOCUMENTATION) ---
local EV_STATUSES_MESSAGES = {
  [0] = "EV Connected",
  [1] = "Relays active (Charging enabled)",
  [2] = "Power delivered",
  [3] = "Charging is paused",
  [4] = "EV ready to accept charge",
  [15] = "Derating (High temp.)",
}

-- --- UTILITY FUNCTIONS FOR ZIGBEE SCALING ---
local function calculate_value(raw_value, attribute_id)
  local factor = scaling_factors[attribute_id]
  if factor and factor.multiplier and factor.divisor and factor.divisor ~= 0 then
    -- Convert the raw integer value to the actual SI unit value
    return raw_value * factor.multiplier / factor.divisor
  else
    -- Fallback for debugging: use raw value if factor is missing
    return raw_value
  end
end

local function store_scaling_factor(device, attr_id, raw_value)
  local measurement_attr_id
  if attr_id == clusters.ElectricalMeasurement.attributes.ACVoltageMultiplier.ID or attr_id == clusters.ElectricalMeasurement.attributes.ACVoltageDivisor.ID then
    measurement_attr_id = clusters.ElectricalMeasurement.attributes.RMSVoltage.ID
  elseif attr_id == clusters.ElectricalMeasurement.attributes.ACCurrentMultiplier.ID or attr_id == clusters.ElectricalMeasurement.attributes.ACCurrentDivisor.ID then
    measurement_attr_id = clusters.ElectricalMeasurement.attributes.RMSCurrent.ID
  elseif attr_id == clusters.ElectricalMeasurement.attributes.ACPowerMultiplier.ID or attr_id == clusters.ElectricalMeasurement.attributes.ACPowerDivisor.ID then
    measurement_attr_id = clusters.ElectricalMeasurement.attributes.ActivePower.ID
  end
  
  if not measurement_attr_id then return end

  if not scaling_factors[measurement_attr_id] then
    scaling_factors[measurement_attr_id] = { multiplier = 1, divisor = 1 }
  end

  if attr_id == clusters.ElectricalMeasurement.attributes.ACVoltageMultiplier.ID or 
     attr_id == clusters.ElectricalMeasurement.attributes.ACCurrentMultiplier.ID or
     attr_id == clusters.ElectricalMeasurement.attributes.ACPowerMultiplier.ID then
      scaling_factors[measurement_attr_id].multiplier = raw_value
  elseif attr_id == clusters.ElectricalMeasurement.attributes.ACVoltageDivisor.ID or
         attr_id == clusters.ElectricalMeasurement.attributes.ACCurrentDivisor.ID or
         attr_id == clusters.ElectricalMeasurement.attributes.ACPowerDivisor.ID then
      scaling_factors[measurement_attr_id].divisor = raw_value
  end
  
  device:set_field(string.format("scaling_0x%04X", measurement_attr_id), scaling_factors[measurement_attr_id])
  log.info(string.format("Updated scaling factor for 0x%04X: M=%d, D=%d", measurement_attr_id, scaling_factors[measurement_attr_id].multiplier, scaling_factors[measurement_attr_id].divisor))
end


-- --- STATUS HANDLING LOGIC ---
local function handle_ev_status(device, status_bitmask)
  local active_statuses = {}
  
  for bit, status_message in pairs(EV_STATUSES_MESSAGES) do
    local mask = 1 << bit
    if (status_bitmask & mask) ~= 0 then
      table.insert(active_statuses, status_message)
    end
  end
  
  local status_string = "Status: " .. (table.concat(active_statuses, " / ") or "Amina Ready")
  
  -- Log the detailed status (for debug and history)
  log.info("Amina EV Status: " .. status_string)
  
  -- Relying on logs, switch state, and measurement data for state visualization.
end

-- --- HANDLERS FOR EVENTS ---

local function handle_switch_cmd(driver, device, command)
  local cmd_id = command.command
  
  if cmd_id == capabilities.switch.commands.on then
    device:send(clusters.OnOff.client.on({}):to_endpoint(CHARGER_ENDPOINT))
  elseif cmd_id == capabilities.switch.commands.off then
    device:send(clusters.OnOff.client.off({}):to_endpoint(CHARGER_ENDPOINT))
  end
end

local function handle_level_cmd(driver, device, command)
  local level_in_percent = command.args.level
  
  -- Conversion: 0-100% -> 6A-32A (Amina min/max supported current)
  local min_amp = 6
  local max_amp = 32
  local amp_value = math.floor(min_amp + (level_in_percent / 100) * (max_amp - min_amp))
  
  log.info(string.format("Setting Charge Limit (Level) to: %d Amps (from %d%%)", amp_value, level_in_percent))
  
  -- Use Move To Level With On/Off (0x04) to set current and ensure charging is armed
  device:send(clusters.LevelControl.client.move_to_level_with_on_off({
      level = amp_value,
      transition_time = 0
    }):to_endpoint(CHARGER_ENDPOINT))
end

local function electrical_measurement_handler(driver, device, event, raw_data)
  local attr_id = event.attr_id
  local raw_value = event.value.value
  local final_value
  
  -- 1. Store Scaling Factors first
  if attr_id >= clusters.ElectricalMeasurement.attributes.ACVoltageMultiplier.ID and attr_id <= clusters.ElectricalMeasurement.attributes.ACPowerDivisor.ID then
    store_scaling_factor(device, attr_id, raw_value)
  end

  -- 2. Handle Measurement Values (Use stored factors)
  if attr_id == clusters.ElectricalMeasurement.attributes.RMSVoltage.ID then
    final_value = calculate_value(raw_value, attr_id)
    device:emit_event(capabilities.voltageMeasurement.voltage({value = final_value, unit = "V"}))
    return
  elseif attr_id == clusters.ElectricalMeasurement.attributes.RMSCurrent.ID then
    final_value = calculate_value(raw_value, attr_id)
    device:emit_event(capabilities.currentMeasurement.current({value = final_value, unit = "A"}))
    return
  elseif attr_id == clusters.ElectricalMeasurement.attributes.ActivePower.ID then
    final_value = calculate_value(raw_value, attr_id)
    device:emit_event(capabilities.powerMeter.power({value = final_value, unit = "W"}))
    return
  end
  
  return defaults.basic_response_handler(driver, device, event, raw_data)
end

local function handle_alarms(device, alarm_bitmask)
  local active_alarms = {}
  local is_critical = false
  
  if alarm_bitmask == 0 then
    log.info("Amina S: No active alarms reported.")
    return
  end
  
  log.warn(string.format("Amina S: Alarm detected (Bitmask: 0x%X).", alarm_bitmask))

  for bit = 0, 11 do
    local mask = 1 << bit
    if (alarm_bitmask & mask) ~= 0 then
      local message = ALARM_MESSAGES[bit] or string.format("Unknown Alarm Bit %d", bit)
      table.insert(active_alarms, message)
      if bit < 5 or bit == 10 then is_critical = true end -- Alarms 0-4 and 10 are Safety/Critical
    end
  end
  
  if #active_alarms > 0 then
    local final_message = "Charger Status: " .. active_alarms[1]
    if #active_alarms > 1 then
      final_message = final_message .. " (and " .. (#active_alarms - 1) .. " more issues)"
    end
    
    device:emit_event(capabilities.notification.sendNotification({
      message = final_message,
      level = is_critical and "error" or "warning"
    }))
  end
end

local function amina_control_handler(driver, device, event, raw_data)
  if event.attr_id == AMINA_ENERGY_ATTRIBUTE then
      local watt_hours = event.value.value
      local kwh = watt_hours / 1000.0 -- Convert Wh to kWh
      
      -- Emitting energy event using the 'energy' attribute
      device:emit_event(capabilities.energyMeasurement.energy({
          value = kwh,
          unit = "kWh"
      }))
  elseif event.attr_id == AMINA_ALARMS_ATTRIBUTE then
      -- Alarm bitmask received
      local alarm_bitmask = event.value.value
      handle_alarms(device, alarm_bitmask)
  elseif event.attr_id == AMINA_STATUSES_ATTRIBUTE then
      -- EV Statuses bitmask received
      local status_bitmask = event.value.value
      handle_ev_status(device, status_bitmask)
  end
  
  return defaults.basic_response_handler(driver, device, event, raw_data)
end

local function configure_reporting(device)
  log.info("Configuring automatic attribute reporting for Amina S...")
  
  -- On/Off: Report immediately on change
  device:send(clusters.OnOff.client.configure_reporting(
    clusters.OnOff.attributes.OnOff, 0, 0, 600
  ):to_endpoint(CHARGER_ENDPOINT))

  -- ActivePower (W)
  device:send(clusters.ElectricalMeasurement.client.configure_reporting(
    clusters.ElectricalMeasurement.attributes.ActivePower, 30, 300, 5
  ):to_endpoint(CHARGER_ENDPOINT))
  
  -- RMSCurrent (A)
  device:send(clusters.ElectricalMeasurement.client.configure_reporting(
    clusters.ElectricalMeasurement.attributes.RMSCurrent, 30, 300, 500
  ):to_endpoint(CHARGER_ENDPOINT))

  -- Total Active Energy (Wh)
  device:send(clusters.Cluster.client.configure_reporting(
    AMINA_S_CONTROL_CLUSTER, AMINA_ENERGY_ATTRIBUTE, clusters.DataType.UINT32, 300, 3600, 1000
  ):to_endpoint(CHARGER_ENDPOINT))

  -- Alarms (0x0002): Set minimum reporting interval
  device:send(clusters.Cluster.client.configure_reporting(
    AMINA_S_CONTROL_CLUSTER, AMINA_ALARMS_ATTRIBUTE, clusters.DataType.UINT16, 60, 3600, 1
  ):to_endpoint(CHARGER_ENDPOINT))
  
  -- EV Statuses (0x0003): Set minimum reporting interval
  device:send(clusters.Cluster.client.configure_reporting(
    AMINA_S_CONTROL_CLUSTER, AMINA_STATUSES_ATTRIBUTE, clusters.DataType.UINT16, 60, 3600, 1
  ):to_endpoint(CHARGER_ENDPOINT))
end

local function refresh_all_measurements(device)
  -- Read all Scaling Multipliers/Divisors first
  device:send(clusters.ElectricalMeasurement.client.read_attributes({
      clusters.ElectricalMeasurement.attributes.ACVoltageMultiplier,
      clusters.ElectricalMeasurement.attributes.ACVoltageDivisor,
      clusters.ElectricalMeasurement.attributes.ACCurrentMultiplier,
      clusters.ElectricalMeasurement.attributes.ACCurrentDivisor,
      clusters.ElectricalMeasurement.attributes.ACPowerMultiplier,
      clusters.ElectricalMeasurement.attributes.ACPowerDivisor
  }):to_endpoint(CHARGER_ENDPOINT))

  -- Then read the measurement values
  device:send(clusters.ElectricalMeasurement.client.read_attributes({
      clusters.ElectricalMeasurement.attributes.RMSVoltage,
      clusters.ElectricalMeasurement.attributes.RMSCurrent,
      clusters.ElectricalMeasurement.attributes.ActivePower
  }):to_endpoint(CHARGER_ENDPOINT))

  -- Read Total Active Energy, Alarms, and Statuses
  device:send(clusters.Cluster.client.read_attributes(AMINA_S_CONTROL_CLUSTER, {
      AMINA_ENERGY_ATTRIBUTE,
      AMINA_ALARMS_ATTRIBUTE,
      AMINA_STATUSES_ATTRIBUTE
    }):to_endpoint(CHARGER_ENDPOINT))
end

local function do_init(driver, device)
  -- Loads stored scaling factors on startup
  local stored_scaling = device:get_field("scaling_0x0404")
  if stored_scaling then
    log.info("Loaded stored scaling factors for device initialization.")
  end
end

local function do_configure(device)
  -- 1. Configure Reporting (Critical for automatic updates)
  configure_reporting(device)
  
  -- 2. Read initial values and scaling factors
  refresh_all_measurements(device)
end

local amina_driver = zigbee_driver.Driver("amina-s-driver", {
  supported_capabilities = {
    capabilities.switch, 
    capabilities.switchLevel, 
    capabilities.powerMeter, 
    capabilities.voltageMeasurement, 
    capabilities.currentMeasurement,
    capabilities.energyMeasurement,
    capabilities.refresh,
    capabilities.notification
  },
  capability_handlers = {
    [capabilities.switch.ID] = {
      [capabilities.switch.commands.on.NAME] = handle_switch_cmd,
      [capabilities.switch.commands.off.NAME] = handle_switch_cmd
    },
    [capabilities.switchLevel.ID] = {
      [capabilities.switchLevel.commands.setLevel.NAME] = handle_level_cmd
    },
    [capabilities.refresh.ID] = {
        [capabilities.refresh.commands.refresh.NAME] = refresh_all_measurements
    }
  },
  lifecycle_handlers = {
    init = do_init, 
    doConfigure = do_configure 
  },
  configure = defaults.zigbee_handlers.configure_device,
  
  zigbee_handlers = {
    cluster = {
      [ZCL_ON_OFF_CLUSTER] = defaults.zigbee_handlers.on_off_attr_handler,
      [ZCL_LEVEL_CONTROL_CLUSTER] = defaults.zigbee_handlers.level_control_attr_handler,
      [ZCL_ELECTRICAL_MEASUREMENT_CLUSTER] = electrical_measurement_handler, 
      [AMINA_S_CONTROL_CLUSTER] = amina_control_handler, 
    }
  }
})

return amina_driver
