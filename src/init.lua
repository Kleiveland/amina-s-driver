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
local AMINA_S_CONTROL_CLUSTER = 0xFEE7  -- Amina Custom Cluster ID
local AMINA_ENERGY_ATTRIBUTE = 0x0010  -- Total Active Energy (Wh) in 0xFEE7

local CHARGER_ENDPOINT = 10 
local scaling_factors = {}

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


-- --- HANDLERS FOR CAPABILITIES (CONTROL & EVENTS) ---
-- (Ingen endringer i handle_switch_cmd, handle_level_cmd, electrical_measurement_handler, amina_control_handler)
-- [Kode for handle_switch_cmd, handle_level_cmd, electrical_measurement_handler, amina_control_handler]
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
  if attr_id == MEASUREMENT_ATTRIBUTES.voltage then
    final_value = calculate_value(raw_value, attr_id)
    device:emit_event(capabilities.voltageMeasurement.voltage({value = final_value, unit = "V"}))
    return
  elseif attr_id == MEASUREMENT_ATTRIBUTES.current then
    final_value = calculate_value(raw_value, attr_id)
    device:emit_event(capabilities.currentMeasurement.current({value = final_value, unit = "A"}))
    return
  elseif attr_id == MEASUREMENT_ATTRIBUTES.power then
    final_value = calculate_value(raw_value, attr_id)
    device:emit_event(capabilities.powerMeter.power({value = final_value, unit = "W"}))
    return
  end
  
  return defaults.basic_response_handler(driver, device, event, raw_data)
end


local function amina_control_handler(driver, device, event, raw_data)
  if event.attr_id == AMINA_ENERGY_ATTRIBUTE then
      local watt_hours = event.value.value
      local kwh = watt_hours / 1000.0 -- Convert Wh to kWh
      
      device:emit_event(capabilities.energyMeasurement.energy({
          value = kwh,
          unit = "kWh"
      }))
      return
  end
  
  -- TODO: Add robust handling for Alarms (0x0002) and EV Statuses (0x0003) here,
  -- converting the bitmask to readable status messages based on Amina documentation.
  return defaults.basic_response_handler(driver, device, event, raw_data)
end
-- [Slutt på funksjonskroppene]

-- Function to configure attribute reporting
local function configure_reporting(device)
  log.info("Configuring automatic attribute reporting for Amina S...")
  
  -- 0x0006 On/Off: Report immediately on change
  device:send(clusters.OnOff.client.configure_reporting(
    clusters.OnOff.attributes.OnOff, 
    0, 
    0, 
    600 -- Max interval 10 minutes
  ):to_endpoint(CHARGER_ENDPOINT))

  -- 0x0B04 Electrical Measurement: Report ActivePower (W)
  -- Report min once every 30s, max once every 300s (5 min), and on a change threshold (e.g., 5 Watts)
  device:send(clusters.ElectricalMeasurement.client.configure_reporting(
    clusters.ElectricalMeasurement.attributes.ActivePower, 
    30, 
    300, 
    5 -- Report on 5 Watt change threshold
  ):to_endpoint(CHARGER_ENDPOINT))
  
  -- 0x0B04 Electrical Measurement: Report RMSCurrent (A)
  -- Report min once every 30s, max once every 300s (5 min), and on a change threshold (e.g., 5 Amps)
  device:send(clusters.ElectricalMeasurement.client.configure_reporting(
    clusters.ElectricalMeasurement.attributes.RMSCurrent, 
    30, 
    300, 
    500 -- Note: Assuming current is reported in milliAmps (0.5A threshold) based on common practice.
  ):to_endpoint(CHARGER_ENDPOINT))

  -- 0xFEE7 Amina S Control: Report Total Active Energy (Wh)
  device:send(clusters.Cluster.client.configure_reporting(
    AMINA_S_CONTROL_CLUSTER, 
    AMINA_ENERGY_ATTRIBUTE, 
    clusters.DataType.UINT32, 
    300, -- Min interval 5 minutes
    3600, -- Max interval 1 hour
    1000 -- Report on 1000 Wh (1 kWh) change
  ):to_endpoint(CHARGER_ENDPOINT))
end

-- Function to read all attributes and scaling factors (used for manual refresh)
local function refresh_all_measurements(device)
  -- [Koden fra den forrige refresh_all_measurements funksjonen er her]
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

  -- Read Total Active Energy and Statuses
  device:send(clusters.Cluster.client.read_attributes(AMINA_S_CONTROL_CLUSTER, {
      AMINA_ENERGY_ATTRIBUTE 
      -- 0x0002 Alarms
      -- 0x0003 EV Statuses
    }):to_endpoint(CHARGER_ENDPOINT))
end

local function do_configure(device)
  -- 1. Configure Reporting (Critical for automatic updates)
  configure_reporting(device)
  
  -- 2. Read initial values and scaling factors
  refresh_all_measurements(device)
end

-- --- DRIVER DEFINITION ---

local amina_driver = zigbee_driver.Driver("amina-s-driver", {
  supported_capabilities = {
    capabilities.switch, 
    capabilities.switchLevel, 
    capabilities.powerMeter, 
    capabilities.voltageMeasurement, 
    capabilities.currentMeasurement,
    capabilities.energyMeasurement,
    capabilities.refresh
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
    doConfigure = do_configure -- Run configuration and initial refresh on install
  },
  zigbee_handlers = {
    cluster = {
      [ZCL_ON_OFF_CLUSTER] = defaults.zigbee_handlers.on_off_attr_handler,
      [ZCL_LEVEL_CONTROL_CLUSTER] = defaults.zigbee_handlers.level_control_attr_handler,
      [ZCL_ELECTRICAL_MEASUREMENT_CLUSTER] = electrical_measurement_handler, -- Custom handler for scaling
      [AMINA_S_CONTROL_CLUSTER] = amina_control_handler, -- Custom handler for custom cluster
    }
  }
})

return amina_driver
