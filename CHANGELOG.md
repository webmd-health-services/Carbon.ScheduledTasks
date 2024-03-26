
# Carbon.ScheduledTasks Changelog

## 1.0.0

### Migration Instructions

If migrating from Carbon, follow these migration instructions.

The type of objects returned by the types of some parameters of `Get-CSCheduledTask` and `Install-CSCheduledTask` have
changed. They are now instances of built-in PowerShell classes or enums. All properties should be the same, but replace
usages of these type *names*:

* `[Carbon.TaskScheduler.Month]` → `[Carbon_ScheduledTasks_Month]`
* `[Carbon.TaskScheduler.ScheduleInfo]` → `[Carbon_ScheduledTasks_ScheduleInfo]`
* `[Carbon.TaskScheduler.ScheduleType]` → `[Carbon_ScheduledTasks_ScheduleType]`
* `[Carbon.TaskScheduler.TaskInfo]` → `[Carbon_ScheduledTasks_TaskInfo]`
* `[Carbon.TaskScheduler.WeekOfMonth]` → `[Carbon_ScheduledTasks_WeekOfMonth]`
