
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

BeforeAll {
    Set-StrictMode -Version 'Latest'

    & (Join-Path -Path $PSScriptRoot -ChildPath 'Initialize-Test.ps1' -Resolve)
}

Describe 'Test-CScheduledTask' {
    BeforeEach {
        $Global:Error.Clear()
    }

    It 'should find existing task' {
        $task = Get-CScheduledTask | Select-Object -First 1
        $task | Should -Not -BeNullOrEmpty
        (Test-CScheduledTask -Name $task.FullName) | Should -BeTrue
        $Global:Error.Count | Should -Be 0
    }

    It 'should not find non existent task' {
        (Test-CScheduledTask -Name 'fubar') | Should -BeFalse
        $Global:Error.Count | Should -Be 0
    }
}
