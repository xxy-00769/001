param([string]$Case)
[Console]::OutputEncoding=New-Object Text.UTF8Encoding($false)
[Console]::Write('PROMPT_WITHOUT_NEWLINE:')
if($Case -ne 'missing') {
    $data=@{experiment='NET2_OFFICIAL_BASELINE_E1_NOT_FUNCTIONAL_RELEASE'; window_seconds=10;
        interface='eth0'; raw_arp_requests_sent=20; hardware_crc_delta=$null;
        received_board_arp_requests=0; received_board_arp_replies=0;
        tx_physical_baseline_pass=$null; arp_roundtrip_baseline_pass=$false;
        before=@{}; after=@{}; padding=('X'*20000)}
    $s="`n=== E1_SAMPLE_JSON_BEGIN ===`n"+($data|ConvertTo-Json)+"`n=== E1_SAMPLE_JSON_END ===`n"
    [Console]::Out.Write($s.Substring(0,10000))
    [Console]::Error.WriteLine('Connection to fixture closed.')
    [Console]::Out.Write($s.Substring(10000))
}
if($Case -eq 'python_error'){[Console]::Error.WriteLine('Simulated Python failure'); exit 7}
exit 0
