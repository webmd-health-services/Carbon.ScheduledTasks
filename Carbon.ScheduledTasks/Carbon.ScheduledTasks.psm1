# Copyright WebMD Health Services
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License

using namespace System.Collections.Generic;

#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

# Functions should use $moduleRoot as the relative root from which to find
# things. A published module has its function appended to this file, while a
# module in development has its functions in the Functions directory.
$script:moduleRoot = $PSScriptRoot

$psModulesRoot = Join-Path -Path $script:moduleRoot -ChildPath 'M' -Resolve
Import-Module -Name (Join-Path -Path $psModulesRoot -ChildPath 'Carbon.Core' -Resolve) `
              -Function @('Add-CTypeData') `
              -Verbose:$false
Import-Module -Name (Join-Path -Path $psModulesRoot -ChildPath 'Carbon.Accounts' -Resolve) `
              -Function @('Resolve-CPrincipalName') `
              -Verbose:$false
Import-Module -Name (Join-Path -Path $psModulesRoot -ChildPath 'Carbon.Security' -Resolve) `
              -Function @('Grant-CPrivilege') `
              -Verbose:$false

enum Carbon_ScheduledTasks_Month
{
    January = 1
    February
    March
    April
    May
    June
    July
    August
    September
    October
    November
    December
}

enum Carbon_ScheduledTasks_WeekOfMonth
{
    First = 1
    Second
    Third
    Fourth
    Last
}

enum Carbon_ScheduledTasks_ScheduleType
{
    Unknown
    Minute
    Hourly
    Daily
    Weekly
    Monthly
    Once
    OnLogon
    OnStart
    OnIdle
    OnEvent
    Registration
    SessionStateChange
    OnDemand
}

class Carbon_ScheduledTasks_ScheduleInfo
{
    Carbon_ScheduledTasks_ScheduleInfo()
    {
    }

    [int[]] $Days
    [DayOfWeek[]] $DaysOfWeek
    [TimeSpan] $Delay
    [DateTime] $EndDate
    [TimeSpan] $EndTime
    [String] $EventChannelName
    [int] $IdleTime
    [int] $Interval
    [int] $LastResult
    [String] $Modifier
    [Carbon_ScheduledTasks_Month[]] $Months
    [String] $RepeatEvery
    [String] $RepeatStopIfStillRunning
    [String] $RepeatUntilDuration
    [String] $RepeatUntilTime
    [bool] $StopAtEnd
    [String] $StopTaskIfRunsXHoursandXMins
    [Carbon_ScheduledTasks_ScheduleType] $ScheduleType
    [DateTime] $StartDate
    [TimeSpan] $StartTime

}

class Carbon_ScheduledTasks_TaskInfo
{
    Carbon_ScheduledTasks_TaskInfo(
        [String] $hostName, [String] $path, [String] $name, [String] $nextRunTime, [String] $status,
        [String] $logonMode, [String] $lastRunTime, [String] $author, [DateTime] $createDate, [String] $taskToRun,
        [String] $startIn, [String] $comment, [String] $scheduledTaskState, [String] $idleTime,
        [String] $powerManagement, [String] $runAsUser, [bool] $interactive, [bool] $noPassword,
        [bool] $highestAvailableRunLevel, [String] $deleteTaskIfNotRescheduled)
    {
        $this.HostName = $hostName;
        $this.TaskPath = $path;
        $this.TaskName = $name;
        $this.NextRunTime = $nextRunTime;
        $this.Status = $status;
        $this.LogonMode = $logonMode;
        $this.LastRunTime = $lastRunTime;
        $this.Author = $author;
        $this.CreateDate = $createDate;
        $this.TaskToRun = $taskToRun;
        $this.StartIn = $startIn;
        $this.Comment = $comment;
        $this.ScheduledTaskState = $scheduledTaskState;
        $this.IdleTime = $idleTime;
        $this.PowerManagement = $powerManagement;
        $this.RunAsUser = $runAsUser;
        $this.Interactive = $interactive;
        $this.NoPassword = $noPassword;
        $this.HighestAvailableRunLevel = $highestAvailableRunLevel;
        $this.DeleteTaskIfNotRescheduled = $deleteTaskIfNotRescheduled;
        $this.Schedules = [List[Object]]::New();
    }

    [String] $Author
    [String] $Comment
    [DateTime] $CreateDate
    [String] $DeleteTaskIfNotRescheduled
    [bool] $HighestAvailableRunLevel
    [String] $HostName
    [String] $IdleTime
    [bool] $Interactive
    [String] $LastRunTime
    [String] $LogonMode
    [String] $NextRunTime
    [bool] $NoPassword
    [String] $PowerManagement
    [String] $RunAsUser
    [IList[Object]] $Schedules
    [String] $ScheduledTaskState
    [String] $StartIn
    [String] $Status
    [String] $TaskToRun
    [String] $TaskName
    [String] $TaskPath
}

Add-CTypeData -Type ([Carbon_ScheduledTasks_TaskInfo]) -MemberType AliasProperty -MemberName 'State' -Value 'Status'
Add-CTypeData -Type ([Carbon_ScheduledTasks_TaskInfo]) `
              -MemberType ScriptProperty `
              -MemberName 'FullName' `
              -Value { return Join-Path -Path $this.TaskPath -ChildPath $this.TaskName }

# Store each of your module's functions in its own file in the Functions
# directory. On the build server, your module's functions will be appended to
# this file, so only dot-source files that exist on the file system. This allows
# developers to work on a module without having to build it first. Grab all the
# functions that are in their own files.
$functionsPath = Join-Path -Path $script:moduleRoot -ChildPath 'Functions\*.ps1'
if( (Test-Path -Path $functionsPath) )
{
    foreach( $functionPath in (Get-Item $functionsPath) )
    {
        . $functionPath.FullName
    }
}
