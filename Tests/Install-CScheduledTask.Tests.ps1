
using module ..\Carbon.ScheduledTasks;

#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

BeforeAll {
    Set-StrictMode -Version 'Latest'

    & (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-Test.ps1' -Resolve)

    $psModulesPath = Join-Path -Path $PSScriptRoot -ChildPath '..\PSModules' -Resolve
    Import-Module -Name (Join-Path -Path $psModulesPath -ChildPath 'Carbon' -Resolve) `
                  -Function @('Install-CUser') `
                  -Verbose:$false
    $privateModulesPath = Join-Path -Path $PSScriptRoot -ChildPath '..\Carbon.ScheduledTasks\M' -Resolve
    Import-Module -Name (Join-Path -Path $privateModulesPath -ChildPath 'Carbon.Accounts' -Resolve) `
                  -Function @('Resolve-CPrincipalName') `
                  -Verbose:$false

    $script:taskXmlPathWithPrincipal = Join-Path -Path $PSScriptRoot -ChildPath 'ScheduledTasks\task_with_principal.xml'
    $script:taskXmlWithPrincipal = (Get-Content -Path $script:taskXmlPathWithPrincipal) -join ([Environment]::NewLine)

    $script:taskName = $null
    $script:credential = $null
    $script:AllMonths = @( 'January','February','March','April','May','June','July','August','September','October','November','December' )
    $script:today = Get-Date
    $script:today = New-Object 'DateTime' $script:today.Year,$script:today.Month,$script:today.Day
    $script:testNum = 0

    $script:credential =
        [pscredential]::New('CarbonInstallSchedul', (ConvertTo-SecureString -String 'a1b2c34d!' -Force -AsPlainText))
    Install-CUser -Credential $script:credential -Description 'Test user for running scheduled tasks.'

    function Assert-TaskScheduledFromXml
    {
        [CmdletBinding(DefaultParameterSetName='BuiltinAccount')]
        param(
            $Path,

            $Xml,

            [Parameter(ParameterSetName='BuiltinAccount')]
            [String] $RunsAsBuiltInAccount,

            [Parameter(ParameterSetName='CustomCredential')]
            [pscredential] $TaskCredential
        )

        Set-StrictMode -Version 'Latest'

        $installParams = @{ }
        if ($TaskCredential)
        {
            $installParams['TaskCredential'] = $TaskCredential
        }

        if ($RunsAsBuiltInAccount)
        {
            $installParams['Principal'] = $RunsAsBuiltInAccount
        }

        if( $Path )
        {
            $installParams['TaskXmlFilePath'] = $Path
        }

        if( $Xml )
        {
            $installParams['TaskXml'] = $Xml
        }

        $task = Install-CScheduledTask -Name $script:taskName @installParams
        $task | Should -Not -BeNullOrEmpty
        $Global:Error.Count | Should -Be 0
        # Now, make sure task doesn't get re-created if it already exists.
        (Install-CScheduledTask -Name $script:taskName @installParams) | Should -BeNullOrEmpty
        $Global:Error.Count | Should -Be 0
        $task = Get-CScheduledTask -Name $script:taskName -AsComObject
        $task | Should -Not -BeNullOrEmpty
        $task.Path | Should -Be (Join-Path -Path '\' -ChildPath $script:taskName)
        if( $TaskCredential )
        {
            $task.Definition.Principal.UserId | Should -Match "\b$([regex]::Escape($TaskCredential.Username))$"
        }
        else
        {
            if (-not $RunsAsBuiltInAccount)
            {
                $RunsAsBuiltInAccount = 'System'
            }
            $expectedUserId = Resolve-CPrincipalName -Name $RunsAsBuiltInAccount
            $task.Definition.Principal.UserId | Should -Be ($expectedUserId | Split-Path -Leaf)
        }

        if( $Path )
        {
            $Xml = [xml]((Get-Content -Path $Path) -join ([Environment]::NewLine))
        }
        else
        {
            $Xml = [xml]$Xml
        }

        $task = Get-CScheduledTask -Name $task.Path -AsComObject
        $actualXml = [xml]$task.Xml
        # Different versions of Windows puts different values in these elements.
        $canonicalizeRegex = '<(Uri|UserId|LogonType|RunLevel)>[^<]*</(Uri|UserId|LogonType|RunLevel)>'
        ($actualXml.OuterXml -replace $canonicalizeRegex,'') |
            Should -Be ($Xml.OuterXml -replace $canonicalizeRegex,'')

        if( $Path )
        {
            $Path | Should -Exist
        }
        else
        {
            (Get-ChildItem -Path $env:TEMP 'Carbon+Install-CScheduledTask+*') | Should -BeNullOrEmpty
        }
    }

    function Assert-TaskScheduled
    {
        [CmdletBinding()]
        param(
            [hashtable]
            $InstallArguments,

            [hashtable]
            $AssertArguments
        )

        Set-StrictMode -Version Latest

        $InstallArguments['Name'] = $script:taskName
        $InstallArguments['TaskToRun'] = 'notepad'

        $AssertArguments['Name'] = $script:taskName
        $AssertArguments['TaskToRun'] = 'notepad'

        # Install to run as SYSTEM
        $task = Install-CScheduledTask -Principal System @InstallArguments
        $Global:Error.Count | Should -Be 0
        $task | Should -Not -BeNullOrEmpty
        $task | Should -BeOfType ([Carbon_ScheduledTasks_TaskInfo])
        Assert-ScheduledTask -Principal 'System' @AssertArguments

        $preTask = Get-CScheduledTask -Name $script:taskName -AsComObject
        (Install-CScheduledTask -Principal System @InstallArguments) | Should -BeNullOrEmpty
        $Global:Error.Count | Should -Be 0
        $postTask = Get-CScheduledTask -Name $script:taskName -AsComObject
        $postTask.Definition.RegistrationInfo.Date | Should -Be $preTask.Definition.RegistrationInfo.Date

        $InstallArguments['TaskCredential'] = $script:credential
        $InstallArguments['Force'] = $true
        $AssertArguments['TaskCredential'] = $script:credential

        $task = Install-CScheduledTask @InstallArguments
        $Global:Error.Count | Should -Be 0
        $task | Should -Not -BeNullOrEmpty
        $task | Should -BeOfType ([Carbon_ScheduledTasks_TaskInfo])
        Assert-ScheduledTask @AssertArguments

        # Install to start tomorrow
        # Check interval parameter
        $intervalSchedules = @( 'Daily', 'Weekly', 'Monthly', 'Month', 'LastDayOfMonth', 'WeekOfMonth' )
        foreach( $intervalSchedule in $intervalSchedules )
        {
            if( $InstallArguments.ContainsKey( $intervalSchedule ) )
            {
                $task = Install-CScheduledTask @InstallArguments -Interval 37
                $task | Should -Not -BeNullOrEmpty
                $task | Should -BeOfType ([Carbon_ScheduledTasks_TaskInfo])
                Assert-ScheduledTask @AssertArguments -Interval 37
                break
            }
        }

        if( -not $InstallArguments.ContainsKey('StartTime') )
        {
            $startTimeSchedules = @( 'Daily', 'Weekly', 'Monthly', 'Month', 'LastDayOfMonth', 'WeekOfMonth', 'Once' )
            foreach( $startTimeSchedule in $startTimeSchedules )
            {
                if( $InstallArguments.ContainsKey( $startTimeSchedule ) )
                {
                    $task = Install-CScheduledTask @InstallArguments -StartTime '23:06'
                    $Global:Error.Count | Should -Be 0
                    $task | Should -Not -BeNullOrEmpty
                    $task | Should -BeOfType ([Carbon_ScheduledTasks_TaskInfo])
                    Assert-ScheduledTask @AssertArguments -StartTime '23:06'
                    break
                }
            }
        }

        $startDateSchedules =  @( 'Minute','Daily', 'Weekly', 'Monthly', 'Month', 'LastDayOfMonth', 'WeekOfMonth', 'Once' )
        foreach( $startDateSchedule in $startDateSchedules )
        {
            if( $InstallArguments.ContainsKey( $startDateSchedule ) )
            {
                $task = Install-CScheduledTask @InstallArguments -StartDate $script:today.AddDays(1)
                $Global:Error.Count | Should -Be 0
                $task | Should -Not -BeNullOrEmpty
                $task | Should -BeOfType ([Carbon_ScheduledTasks_TaskInfo])
                Assert-ScheduledTask @AssertArguments -StartDate $script:today.AddDays(1)
            }
        }

        $durationSchedules = @( 'Minute', 'Daily', 'Weekly', 'Monthly', 'LastDayOfMonth', 'WeekOfMonth' )
        foreach( $durationSchedule in $durationSchedules )
        {
            if( $InstallArguments.ContainsKey( $durationSchedule ) )
            {
                $task = Install-CScheduledTask @InstallArguments -Duration '5:30'  # Using fractional hours to ensure it gets converted properly.
                $Global:Error.Count | Should -Be 0
                $task | Should -Not -BeNullOrEmpty
                $task | Should -BeOfType ([Carbon_ScheduledTasks_TaskInfo])
                Assert-ScheduledTask @AssertArguments -Duration '5:30'
                break
            }
        }

        $endDateSchedules = @( 'Daily', 'Weekly', 'Monthly', 'LastDayOfMonth', 'WeekOfMonth' )
        foreach( $endDateSchedule in $endDateSchedules )
        {
            if( $InstallArguments.ContainsKey( $endDateSchedule ) )
            {
                $task = Install-CScheduledTask @InstallArguments -EndDate $script:today.AddYears(1)
                $Global:Error.Count | Should -Be 0
                $task | Should -Not -BeNullOrEmpty
                $task | Should -BeOfType ([Carbon_ScheduledTasks_TaskInfo])
                Assert-ScheduledTask @AssertArguments -EndDate $script:today.AddYears(1)
                break
            }
        }

        $endTimeSchedules = @( 'Minute', 'Hourly', 'Daily', 'Weekly', 'Monthly', 'LastDayOfMonth', 'WeekOfMonth' )
        $endTime = (Get-Date).AddHours(7)
        foreach( $endTimeSchedule in $endTimeSchedules )
        {
            if( $InstallArguments.ContainsKey( $endTimeSchedule ) )
            {
                $endTimeParams = @{
                                        EndDate = $endTime.ToString('MM/dd/yyyy')
                                        EndTime = $endTime.ToString('HH:mm');
                                    }
                $task = Install-CScheduledTask @InstallArguments @endTimeParams
                $Global:Error.Count | Should -Be 0
                $task | Should -Not -BeNullOrEmpty
                $task | Should -BeOfType ([Carbon_ScheduledTasks_TaskInfo])
                Assert-ScheduledTask @AssertArguments @endTimeParams
                break
            }
        }

        # Install as interactive
        $task = Install-CScheduledTask @InstallArguments -Interactive
        $Global:Error | Should -BeNullOrEmpty
        $task | Should -Not -BeNullOrEmpty
        $task | Should -BeOfType ([Carbon_ScheduledTasks_TaskInfo])
        Assert-ScheduledTask @AssertArguments -Interactive

        # Install as no password
        $task = Install-CScheduledTask @InstallArguments -NoPassword
        $Global:Error | Should -BeNullOrEmpty
        $task | Should -Not -BeNullOrEmpty
        $task | Should -BeOfType ([Carbon_ScheduledTasks_TaskInfo])
        Assert-ScheduledTask @AssertArguments -NoPassword

        # Install as highest run level
        $task = Install-CScheduledTask @InstallArguments -HighestAvailableRunLevel
        $Global:Error.Count | Should -Be 0
        $task | Should -Not -BeNullOrEmpty
        $task | Should -BeOfType ([Carbon_ScheduledTasks_TaskInfo])
        Assert-ScheduledTask @AssertArguments -HighestAvailableRunLevel

        $delaySchedules = @( 'OnStart', 'OnLogon', 'OnEvent' )
        foreach( $delaySchedule in $delaySchedules )
        {
            if( $InstallArguments.ContainsKey( $delaySchedule ) )
            {
                $task = Install-CScheduledTask @InstallArguments -Delay '6.22:39:59'
                $Global:Error.Count | Should -Be 0
                $task | Should -Not -BeNullOrEmpty
                $task | Should -BeOfType ([Carbon_ScheduledTasks_TaskInfo])
                Assert-ScheduledTask @AssertArguments -Delay '6.22:39:59'
                break
            }
        }


    }

    function Assert-ScheduledTask
    {
        [CmdletBinding()]
        param(
            $Name,
            $TaskToRun,
            [pscredential] $TaskCredential,
            $Principal,
            $TaskXmlPath,
            $ScheduleType,
            $Modifier,
            [int[]] $DayOfMonth,
            [DayOfWeek[]] $DayOfWeek,
            [Carbon_ScheduledTasks_Month[]] $Months,
            [int] $IdleTime,
            [TimeSpan] $StartTime,
            $Interval,
            [TimeSpan] $EndTime,
            [TimeSpan] $Duration,
            [switch] $StopAtEnd,
            [DateTime] $StartDate,
            [DateTime] $EndDate,
            $EventChannelName,
            [switch] $Interactive,
            [switch] $NoPassword,
            [switch] $HighestAvailableRunLevel,
            [TimeSpan] $Delay
        )

        Set-StrictMode -Version 'Latest'

        (Test-CScheduledTask -Name $Name) | Should -BeTrue

        $task = Get-CScheduledTask -Name $Name
        $task | Format-List | Out-String | Write-Verbose
        $schedule = $task.Schedules[0]
        $schedule | Format-List | Out-String | Write-Verbose

        $task | Should -Not -BeNullOrEmpty
        # schtasks /query /fo list /v /tn $task.FullName | Write-Verbose
        # schtasks /query /xml /tn $task.FullName | Where-Object { $_ } | Write-Verbose
        $task.TaskToRun.Trim() | Should -Be $TaskToRun

        if( $PSBoundParameters.ContainsKey('TaskCredential') )
        {
            $task.RunAsUser | Should -Match "\b$([regex]::Escape($TaskCredential.Username))$"
        }
        elseif( $PSBoundParameters.ContainsKey('Principal') )
        {
            $task.RunAsUser | Should -Match "\b$([regex]::Escape($Principal))$"
        }
        else
        {
            $task.RunAsUser | Should -Match '\bSYSTEM$'
        }

        if( $HighestAvailableRunLevel )
        {
            $task.HighestAvailableRunLevel | Should -BeTrue
        }
        else
        {
            $task.HighestAvailableRunLevel | Should -BeFalse
        }

        if( $Interactive )
        {
            $task.Interactive | Should -BeTrue
        }
        else
        {
            $task.Interactive | Should -BeFalse
        }

        if( $NoPassword )
        {
            $task.NoPassword | Should -BeTrue
        }
        else
        {
            $task.NoPassword | Should -BeFalse
        }

        if( $PSBoundParameters.ContainsKey('ScheduleType') )
        {
            $schedule.ScheduleType | Should -Be $ScheduleType
        }

        if( $PSBoundParameters.ContainsKey( 'Modifier' ) )
        {
            $schedule.Modifier | Should -Be $Modifier
        }
        else
        {
            $schedule.Modifier | Should -Be ''
        }

        if( $PSBoundParameters.ContainsKey('DayOfMonth') )
        {
            ($schedule.Days -join ',') | Should -Be ($DayOfMonth -join ',')
        }
        else
        {
            $schedule.Days | Should -BeNullOrEmpty
        }

        if( $PSBoundParameters.ContainsKey('DayOfWeek') )
        {
            ($schedule.DaysOfWeek -join ',') | Should -Be ($DayOfWeek -join ',')
        }
        else
        {
            $schedule.DaysOfWeek | Should -BeNullOrEmpty
        }

        if( $PSBoundParameters.ContainsKey('Months') )
        {
            ($schedule.Months -join ', ') | Should -Be ($Months -join ', ')
        }
        else
        {
            $schedule.Months | Should -BeNullOrEmpty
        }

        if( $PSBoundParameters.ContainsKey('StartDate') )
        {
            $schedule.StartDate | Should -Be $StartDate
        }
        else
        {
            if( @('OnLogon', 'OnStart', 'OnIdle', 'OnEvent') -contains $ScheduleType )
            {
                $schedule.StartDate | Should -Be ([DateTime]::MinValue)
            }
            else
            {
                $Schedule.StartDate | Should -Be (New-Object 'DateTime' $script:today.Year,$script:today.Month,$script:today.Day)
            }
        }

        if( $PSBoundParameters.ContainsKey('Duration') )
        {
            $schedule.RepeatUntilDuration | Should -Be $Duration
        }

        if( $StopAtEnd )
        {
            $schedule.StopAtEnd | Should -BeTrue
        }
        else
        {
            $schedule.StopAtEnd | Should -BeFalse
        }

        if( $PSBoundParameters.ContainsKey('Interval') )
        {
            $schedule.Interval | Should -Be $Interval
        }
        else
        {
            if( (@('Daily','Weekly','Monthly','Once') -contains $schedule.ScheduleType) -and ($PSBoundParameters.ContainsKey('EndTime') -or $PSBoundParameters.ContainsKey('Duration')) )
            {
                $schedule.Interval | Should -Be 10
            }
            else
            {
                $schedule.Interval | Should -Be 0
            }
        }

        if( $PSBoundParameters.ContainsKey('StartTime') )
        {
            $schedule.StartTime | Should -Be $StartTime
        }
        else
        {
            if( @('OnLogon', 'OnStart', 'OnIdle', 'OnEvent') -contains $ScheduleType )
            {
                $schedule.StartTime | Should -Be ([TimeSpan]::Zero)
            }
            else
            {
                # Testing equality intermittently fails on build server.
                $schedule.StartTime | Should -BeLessOrEqual (New-Object 'TimeSpan' $task.CreateDate.Hour,($task.CreateDate.Minute + 1),0)
                $schedule.StartTime | Should -BeGreaterOrEqual (New-Object 'TimeSpan' $task.CreateDate.Hour,($task.CreateDate.Minute - 1),0)
            }
        }

        if( $PSBoundParameters.ContainsKey('EndTime') )
        {
            $schedule.EndTime | Should -Be $EndTime
        }
        else
        {
            $schedule.EndTime | Should -Be ([TimeSpan]::Zero)
        }

        if( $PSBoundParameters.ContainsKey('EndDate') )
        {
            $schedule.EndDate | Should -Be $EndDate
        }
        else
        {
            $schedule.EndDate | Should -Be ([datetime]::MaxValue)
        }

        if( $PSBoundParameters.ContainsKey('Delay') )
        {
            $schedule.Delay | Should -Be $Delay
        }
        else
        {
            $schedule.Delay | Should -Be ([TimeSpan]::Zero)
        }

        if( $PSBoundParameters.ContainsKey('IdleTime') )
        {
            $schedule.IdleTime | Should -Be $IdleTime
        }
        else
        {
            $schedule.IdleTime | Should -Be 0
        }

        if( $PSBoundParameters.ContainsKey('EventChannelName') )
        {
            $schedule.EventChannelName | Should -Be $EventChannelName
        }
        else
        {
            $schedule.EventChannelName | Should -BeNullOrEmpty
        }
    }

    function ThenTask
    {
        param(
            [switch] $Exists,

            [String] $RunsAs
        )

        $task = Get-CSCheduledTask -Name $script:taskName

        if ($Exists)
        {
            $task | Should -Not -BeNullOrEmpty
        }

        if ($RunsAs)
        {
            $task.RunAsUser | Should -Be $RunsAS
        }
    }
}

AfterAll {
    Get-CScheduledTask -Name '*CarbonInstallScheduledTask*' -AsComObject |
        ForEach-Object { Uninstall-CScheduledTask -Name $_.Path }
}

Describe 'Install-CScheduledTask' {
    # Windows 2012R2 returns different XML than what we put in so we need to make the resource smarter about its XML
    # difference detection.
    $os = Get-CimInstance Win32_OperatingSystem
    $skip = $os.Caption -like '*2012 R2*'

    BeforeEach {
        $Global:Error.Clear()
        $script:taskName = "CarbonInstallScheduledTask$($script:testNum)"
    }

    AfterEach {
        $script:testNum += 1
    }

    It 'should create scheduled task with path' {
        $fullName = 'PARENT\{0}' -f $script:taskName
        $result = Install-CScheduledTask -Name $fullName -TaskToRun 'notepad' -Monthly -Force
        try
        {
            $result | Should -Not -BeNullOrEmpty
            $result.TaskPath | Should -Be '\PARENT\'
            $result.TaskName | Should -Be $script:taskName
            $result.FullName | Should -Be ('\{0}' -f $fullName)
        }
        finally
        {
            Uninstall-CScheduledTask -Name $fullName
        }
    }

    It 'should schedule per minute tasks' {
        Assert-TaskScheduled -InstallArguments @{ Minute = 5 } -AssertArguments @{ ScheduleType = 'Minute'; Modifier = 5 }
    }

    It 'should schedule hourly tasks' {
        Assert-TaskScheduled -InstallArguments @{ Hourly = 23 } -AssertArguments @{ ScheduleType = 'Hourly'; Modifier = 23 }
    }

    It 'should schedule daily tasks' {
        Assert-TaskScheduled -InstallArguments @{ Daily = 29 } -AssertArguments @{ ScheduleType = 'Daily'; Modifier = 29;  }
    }

    It 'should schedule weekly tasks' {
        Assert-TaskScheduled -InstallArguments @{ Weekly = 39 } -AssertArguments @{ ScheduleType = 'Weekly'; Modifier = 39; DayOfWeek = $script:today.DayOfWeek; }
    }

    It 'should schedule weekly tasks on specific day' {
        Assert-TaskScheduled -InstallArguments @{ Weekly = 39; DayOfWeek = 'Sunday'; } -AssertArguments @{ ScheduleType = 'Weekly'; Modifier = 39; DayOfWeek = 'Sunday'; }
    }

    It 'should schedule weekly tasks on multiple days' {
        Assert-TaskScheduled -InstallArguments @{ Weekly = 39; DayOfWeek = @('Monday','Tuesday','Wednesday'); } -AssertArguments @{ ScheduleType = 'Weekly'; Modifier = 39; DayOfWeek = @('Monday','Tuesday','Wednesday'); }
    }

    It 'should schedule monthly tasks' {
        Assert-TaskScheduled -InstallArguments @{ Monthly = $true; } -AssertArguments @{ ScheduleType = 'Monthly'; Modifier = 1; DayOfMonth = 1; Month = $script:AllMonths }
    }

    It 'should schedule monthly tasks on specific day' {
        Assert-TaskScheduled -InstallArguments @{ Monthly = $true; DayOfMonth = 13; } -AssertArguments @{ ScheduleType = 'Monthly'; Modifier = 1; DayOfMonth = 13; Month = $script:AllMonths }
    }

    It 'should schedule last day of the month task' {
        Assert-TaskScheduled -InstallArguments @{ LastDayOfMonth = $true; } -AssertArguments @{ ScheduleType = 'Monthly'; Modifier = 'LastDay'; Month = $script:AllMonths; }
    }

    It 'should schedule last day of the month task in specific month' {
        Assert-TaskScheduled -InstallArguments @{ LastDayOfMonth = $true; Month = @( 'January' ); } -AssertArguments @{ ScheduleType = 'Monthly'; Modifier = 'LastDay'; Month = @( 'January' ); }
    }

    It 'should schedule last day of the month task in specific months' {
        Assert-TaskScheduled -InstallArguments @{ LastDayOfMonth = $true; Month = @( 'January','June' ); } -AssertArguments @{ ScheduleType = 'Monthly'; Modifier = 'LastDay'; Month = @( 'January','June' ); }
    }

    It 'should schedule for specific month' {
        Assert-TaskScheduled -InstallArguments @{ Month = @( 'January' ); DayOfMonth = 1; } -AssertArguments @{ ScheduleType = 'Monthly'; Month = @( 'January' ); DayOfMonth = 1; }
    }

    It 'should schedule for specific month with integer' {
        Assert-TaskScheduled -InstallArguments @{ Month = @( 1 ); DayOfMonth = 19; } -AssertArguments @{ ScheduleType = 'Monthly'; Month = @( 'January' ); DayOfMonth = 19; }
    }

    It 'should schedule for specific months' {
        Assert-TaskScheduled -InstallArguments @{ Month = @( 'January','April','July','October' ); DayOfMonth = 23; } -AssertArguments @{ ScheduleType = 'Monthly'; Month = @( 'January','April','July','October' ); DayOfMonth = 23; }
    }

    It 'should not schedule monthly task with month parameter' {
        $result = Install-CScheduledTask -Name $script:taskName -Principal LocalService -TaskToRun 'notepad' -Month $script:AllMonths -DayOfMonth 17 -ErrorAction SilentlyContinue
        $Global:Error.Count | Should -BeGreaterThan 0
        $Global:Error[0] | Should -Match 'to schedule a monthly task'
        $result | Should -BeNullOrEmpty
        (Test-CScheduledTask -Name $script:taskName) | Should -BeFalse
    }

    It 'should schedule for specific months on specific day' {
        Assert-TaskScheduled -InstallArguments @{ Month = @( 'January','April','July','October' ); DayOfMonth = 5;  } -AssertArguments @{ ScheduleType = 'Monthly'; Month = @( 'January','April','July','October' ); DayOfMonth = 5; }
    }

    It 'should schedule week of month tasks' {
        Assert-TaskScheduled -InstallArguments @{ WeekOfMonth = 'First'; DayOfWeek = $script:today.DayOfWeek } -AssertArguments @{ ScheduleType = 'Monthly'; Modifier = 'First'; Month = $script:AllMonths; DayOfWeek = $script:today.DayOfWeek; }
    }

    It 'should not schedule week of month on multiple week days' {
        $result = Install-CScheduledTask -Name $script:taskName -Principal LocalService -TaskToRun 'notepad' -WeekOfMonth First -DayOfWeek Friday,Monday -ErrorAction SilentlyContinue
        $Global:Error.Count | Should -BeGreaterThan 0
        $Global:Error[0] | Should -Match 'single weekday'
        $result | Should -BeNullOrEmpty
        (Test-CScheduledTask -Name $script:taskName) | Should -BeFalse
    }

    It 'should schedule week of month tasks on each week' {
        foreach( $week in @( 'First', 'Second', 'Third', 'Fourth', 'Last' ) )
        {
            $result = Install-CScheduledTask -Name $script:taskName -Principal LocalService -TaskToRun 'notepad' -WeekOfMonth $week -DayOfWeek $script:today.DayOfWeek -Force
            $Global:Error.Count | Should -Be 0
            $result | Should -Not -BeNullOrEmpty
            Assert-ScheduledTask -Name $script:taskName -Principal 'Local Service' -TaskToRun 'notepad' -ScheduleType 'Monthly' -Modifier $week -DayOfWeek $script:today.DayOfWeek -Months $script:AllMonths
        }
    }

    It 'should schedule task to run once' {
        Assert-TaskScheduled -InstallArguments @{ Once = $true; StartTime = '3:03' } -AssertArguments @{ ScheduleType = 'Once'; StartTime = '3:03'; }
    }

    It 'should schedule task to run at logon' {
        Assert-TaskScheduled -InstallArguments @{ OnLogon = $true; } -AssertArguments @{ ScheduleType = 'OnLogon'; }
    }

    It 'should schedule task to run at start' {
        Assert-TaskScheduled -InstallArguments @{ OnStart = $true; } -AssertArguments @{ ScheduleType = 'OnStart'; }
    }

    It 'should schedule task to run on idle' {
        Assert-TaskScheduled -InstallArguments @{ OnIdle = 999; } -AssertArguments @{ ScheduleType = 'OnIdle'; IdleTime = 999; }
    }

    It 'should schedule task to run on event' {
        Assert-TaskScheduled -InstallArguments @{ OnEvent = $true ; EventChannelName = 'System' ; EventXPathQuery = '*[System/EventID=101]'; } -AssertArguments @{ ScheduleType = 'OnEvent'; Modifier = '*[System/EventID=101]'; EventChannelName = 'System'; }
    }

    It 'should install from xml file with relative path' -Skip:$skip {
        Push-Location -Path $PSScriptRoot
        try
        {
            Assert-TaskScheduledFromXml -Path '.\ScheduledTasks\task.xml' -TaskCredential $script:credential
        }
        finally
        {
            Pop-Location
        }
    }

    It 'should install from xml file with absolute path' -Skip:$skip {
        Assert-TaskScheduledFromXml -Path (Join-Path -Path $PSScriptRoot -ChildPath 'ScheduledTasks\task.xml') -TaskCredential $script:credential
    }

    It 'should install from xml file for system user' -Skip:$skip {
        Assert-TaskScheduledFromXml -Path (Join-Path -Path $PSScriptRoot -ChildPath 'ScheduledTasks\task_with_principal.xml')
    }

    It 'should install from xml' -Skip:$skip {
        Assert-TaskScheduledFromXml -Xml $script:taskXmlWithPrincipal
    }

    It 'installs from XML as System' {
        Assert-TaskScheduledFromXml -Xml $script:taskXmlWithPrincipal -RunsAsBuiltInAccount 'System'
        ThenTask -Exists -RunsAs 'System'
    }

    It 'installs from XML as LocalService' {
        Assert-TaskScheduledFromXml -Xml $script:taskXmlWithPrincipal -RunsAsBuiltInAccount 'LocalService'
        ThenTask -Exists -RunsAs 'Local Service'
    }

    It 'installs from XML file as NetworkService' {
        Assert-TaskScheduledFromXml -Path $script:taskXmlPathWithPrincipal -RunsAsBuiltInAccount 'NetworkService'
        ThenTask -Exists -RunsAs 'Network Service'
    }
}
