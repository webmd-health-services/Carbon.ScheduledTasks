
using module ..\Carbon.ScheduledTasks;

#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

BeforeAll {
    Set-StrictMode -Version 'Latest'

    & (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-Test.ps1' -Resolve)

    function Assert-ScheduledTaskEqual
    {
        param(
            $Expected,
            $Actual
        )

        Write-Debug ('{0} <=> {1}' -f $Expected.TaskName,$Actual.TaskName)
        $randomNextRunTimeTasks = @{
            '\Microsoft\Office\Office 15 Subscription Heartbeat' = $true;
        }
        $scheduleProps = @(
            'Last Result',
            'Stop Task If Runs X Hours And X Mins',
            'Schedule',
            'Schedule Type',
            'Start Time',
            'Start Date',
            'End Date',
            'Days',
            'Months',
            'Repeat: Every',
            'Repeat: Until: Time',
            'Repeat: Until: Duration',
            'Repeat: Stop If Still Running'
        )

        foreach( $property in (Get-Member -InputObject $Expected -MemberType NoteProperty) )
        {
            $columnName = $property.Name
            if( $scheduleProps -contains $columnName )
            {
                continue
            }

            $propertyName = $columnName -replace '[^A-Za-z0-9_]',''

            Write-Debug ('  {0} <=> {1}' -f $propertyName,$columnName)
            if( $propertyName -eq 'TaskName' )
            {
                $name = Split-Path -Leaf -Path $Expected.TaskName
                $path = Split-Path -Parent -Path $Expected.TaskName
                if( $path -ne '\' )
                {
                    $path = '{0}\' -f $path
                }
                $displayName = ''
                if ($task | Get-Member -Name 'FullName')
                {
                    $displayName = $task.FullName
                }
                elseif (($task | Get-Member -Name 'RegistrationInfo') -and `
                        ($task.RegistrationInfo | Get-Member -Name 'URI'))
                {
                    $displayName = $task.RegistrationInfo.URI
                }
                $Actual.TaskName | Should -Be $name -Because ("${displayName}  TaskName")
                $Actual.TaskPath | Should -Be $path -Because ("${displayName}  TaskPath")
            }
            elseif ($propertyName -in @( 'NextRunTime', 'LastRuntime' ) -and `
                    (
                        $task.FullName -like '\Microsoft\Windows\*' -or `
                        $task.FullName -like '\OneDrive Standalone Update Task*' -or `
                        $randomNextRunTimeTasks.ContainsKey($task.FullName)
                    ) )
            {
                # This task's next run time changes every time you retrieve it.
                continue
            }
            else
            {
                $because = '{0}  {1}' -f $task.FullName,$propertyName
                ($Actual | Get-Member -Name $propertyName) | Should -Not -BeNullOrEmpty -Because $because
                $expectedValue = $Expected.$columnName
                if( $propertyName -eq 'TaskToRun' )
                {
                    $expectedValue = $expectedValue.TrimEnd()

                    if( $expectedValue -like '*"*' )
                    {
                        $actualTask = Get-CScheduledTask -Name $Expected.TaskName -AsComObject
                        if( -not $actualTask.Xml )
                        {
                            Write-Error -Message ('COM object for task "{0}" doesn''t have an XML property or the property doesn''t have a value.' -f $Expected.TaskName)
                        }
                        else
                        {
                            Write-Debug -Message $actualTask.Xml
                            $taskxml = [xml]$actualTAsk.Xml
                            $task = $taskxml.Task
                            if( ($task | Get-Member -Name 'Actions') -and ($task.Actions | Get-Member -Name 'Exec') )
                            {
                                $expectedValue = $taskXml.Task.Actions.Exec.Command
                                if( ($taskxml.Task.Actions.Exec | Get-Member 'Arguments') -and  $taskXml.Task.Actions.Exec.Arguments )
                                {
                                    $expectedValue = '{0} {1}' -f $expectedValue,$taskxml.Task.Actions.Exec.Arguments
                                }
                            }
                        }
                    }

                    # only the first 253 chars come back of the task to run.
                    if ($expectedValue.Length -ge 253)
                    {
                        continue
                    }
                }
                Write-Debug ('    {0} <=> {1}' -f $Actual.$propertyName,$expectedValue)
                ($Actual.$propertyName) | Should -Be $expectedValue -Because $because
            }
        }
    }
}


Describe 'Get-CScheduledTask' {
    BeforeEach {
        $Global:Error.Clear()
    }

    It 'gets each scheduled task' {
        schtasks /query /v /fo csv |
            ConvertFrom-Csv |
            Where-Object { $_.TaskName -and $_.HostName -ne 'HostName' } |
            Where-Object { $_.TaskName -notlike '*Intel*' -and $_.TaskName -notlike '\Microsoft\*' } |  # Some Intel scheduled tasks have characters in their names that don't play well.
            ForEach-Object {
                $expectedTask = $_
                $task = Get-CScheduledTask -Name $expectedTask.TaskName
                $task | Should -Not -BeNullOrEmpty

                Assert-ScheduledTaskEqual $expectedTask $task
            }
    }

    It 'gets schedules' {
        $multiScheduleTasks = Get-CScheduledTask | Where-Object { $_.Schedules.Count -gt 1 }

        $multiScheduleTasks | Should -Not -BeNullOrEmpty

        foreach( $multiScheduleTask in $multiScheduleTasks )
        {
            $expectedSchedules = schtasks /query /v /fo csv /tn $multiScheduleTask.FullName | ConvertFrom-Csv
            $scheduleIdx = 0
            foreach( $expectedSchedule in $expectedSchedules )
            {
                $actualSchedule = $multiScheduleTask.Schedules[$scheduleIdx++]
                $actualSchedule.GetType().FullName | Should -Be ([Carbon_ScheduledTasks_ScheduleInfo].FullName)
            }
        }
    }

    It 'supports wildcards for name' {
        $expectedTask = Get-CScheduledTask -AsComObject | Select-Object -First 1
        $expectedTask | Should -Not -BeNullOrEmpty
        $wildcard = ('*{0}*' -f $expectedTask.Path.Substring(1,$expectedTask.Path.Length - 2))
        $task = Get-CScheduledTask -Name $wildcard
        $task | Should -Not -BeNullOrEmpty
        $task.GetType().FullName | Should -Be ([Carbon_ScheduledTasks_TaskInfo].FullName)
        Join-Path -Path $task.TaskPath -ChildPath $task.TaskName | Should -Be $expectedTask.Path
    }

    It 'gets all scheduled tasks' {
        $expectedTasks = Get-CScheduledTask -AsComObject | Measure-Object
        $actualTasks = Get-CScheduledTask
        $actualTasks.Count | Should -Be $expectedTasks.Count
    }

    It 'ignores non-existent task' {
        $result = Get-CScheduledTask -Name 'fjdskfjsdflkjdskfjsdklfjskadljfksdljfklsdjf' -ErrorAction SilentlyContinue
        $Global:Error.Count | Should -BeGreaterThan 0
        $Global:Error[0] | Should -Match 'not found'
        $result | Should -BeNullOrEmpty
    }
}
