
# Carbon.ScheduledTasks README

## Overview

The "Carbon.ScheduledTasks" module manages Windows scheduled tasks.

## System Requirements

* Windows PowerShell 5.1 and .NET 4.6.2+
* PowerShell 6+

## Installing

To install globally:

```powershell
Install-Module -Name 'Carbon.ScheduledTasks'
Import-Module -Name 'Carbon.ScheduledTasks'
```

To install privately:

```powershell
Save-Module -Name 'Carbon.ScheduledTasks' -Path '.'
Import-Module -Name '.\Carbon.ScheduledTasks'
```

## Commands

* `Get-CScheduledTask` for getting scheduled tasks.
* `Install-CScheduledTask` for installing a scheduled task.
* `Test-CScheduledTask` for checking if a scheduled task exists or not.
* `Uninstall-CScheduledTask` for uninstalling a scheduled task.
