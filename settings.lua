data:extend({
  {
    type = "int-setting",
    name = "wp-trains-radar-radius",
    setting_type = "runtime-global",
    default_value = 2,
    minimum_value = 0,
    maximum_value = 8,
    order = "a"
  },
  {
    type = "int-setting",
    name = "wp-trains-radar-interval",
    setting_type = "runtime-global",
    default_value = 120,
    minimum_value = 10,
    maximum_value = 3600,
    order = "b"
  },
  {
    type = "int-setting",
    name = "wp-trains-radar-parked-interval",
    setting_type = "runtime-global",
    default_value = 30,
    minimum_value = 0,
    maximum_value = 3600,
    order = "c"
  }
})
