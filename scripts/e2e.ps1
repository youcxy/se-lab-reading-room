param([string]$Base = "http://127.0.0.1:8080")

$script:pass = 0
$script:fail = 0
$script:lines = New-Object System.Collections.Generic.List[string]

function Api {
    param([string]$Method, [string]$Path, $Body)
    $p = @{ Method = $Method; Uri = "$Base$Path"; TimeoutSec = 20 }
    if ($null -ne $Body) {
        $p.ContentType = "application/json; charset=utf-8"
        $p.Body = ($Body | ConvertTo-Json -Compress -Depth 6)
    }
    try { return Invoke-RestMethod @p }
    catch {
        $msg = $_.Exception.Message
        if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $msg = $_.ErrorDetails.Message }
        return [pscustomobject]@{ code = -1; message = $msg; data = $null }
    }
}

function Note { param([string]$Text) $script:lines.Add("  - " + $Text) | Out-Null }

function Check {
    param([string]$Name, $Actual, $Expected)
    $a = "$Actual"
    $e = "$Expected"
    if ($a -eq $e) {
        $script:pass++
        $script:lines.Add("PASS  $Name = $a") | Out-Null
    } else {
        $script:fail++
        $script:lines.Add("FAIL  $Name expected=$e actual=$a") | Out-Null
    }
}

function Section { param([string]$Title) $script:lines.Add("") | Out-Null; $script:lines.Add("== $Title ==") | Out-Null }

# ---------- Phase A: base rules ----------
Section "A0 reset"
(Check "clock.reset.code" (Api POST "/api/clock/reset" $null).code 0)

Section "A2 timeout (15 min, credit -10, 4.00 penalty, idempotent)"
$r = Api POST "/api/seats/2/reserve" @{ userId = 2 }
Check "reserve.A02.code" $r.code 0
Check "reserve.A02.unitPrice" $r.data.unitPrice "4.00"
$rid = $r.data.id
Check "clock.advance20" (Api PUT "/api/clock" @{ advanceMinutes = 20 }).data.offsetSeconds 1200
Check "timeout.run1.handled" (Api POST "/api/timeout/run" $null).data 1
Check "timeout.run2.handled" (Api POST "/api/timeout/run" $null).data 0
$u = (Api GET "/api/users" $null).data | Where-Object { $_.id -eq 2 }
Check "timeout.user2.credit" $u.credit 90
$resv = (Api GET "/api/reservations/$rid" $null).data
Check "timeout.reservation.status" $resv.status "EXPIRED"
$dash0 = (Api GET "/api/dashboard" $null).data
Check "timeout.orders" $dash0.orders 1
Check "timeout.revenue" $dash0.revenue "4.00"

Section "A3 usage billing 30 minutes at 4.00 -> 2.00"
$r = Api POST "/api/seats/1/reserve" @{ userId = 1 }
Check "reserve.A01.code" $r.code 0
$rid1 = $r.data.id
Check "checkin.A01" (Api POST "/api/reservations/$rid1/checkin" @{ userId = 1 }).data.status "IN_USE"
(Check "clock.advance30" (Api PUT "/api/clock" @{ advanceMinutes = 30 }).data.offsetSeconds 3000)
$bill = (Api POST "/api/reservations/$rid1/checkout" @{ userId = 1 }).data
Check "usage.minutes" $bill.minutes 30
Check "usage.unitPrice" $bill.unitPrice "4.00"
Check "usage.amount" $bill.amount "2.00"
Check "usage.kind" $bill.kind "USAGE"
Check "usage.source" $bill.source "CLOUD"

Section "A4 monthly card 60 minutes -> 0.00"
$r = Api POST "/api/seats/3/reserve" @{ userId = 3 }
Check "reserve.A03.code" $r.code 0
$rid2 = $r.data.id
(Api POST "/api/reservations/$rid2/checkin" @{ userId = 3 }) | Out-Null
(Api PUT "/api/clock" @{ advanceMinutes = 60 }) | Out-Null
$bill2 = (Api POST "/api/reservations/$rid2/checkout" @{ userId = 3 }).data
Check "monthly.amount" $bill2.amount "0.00"
Check "monthly.cardType" $bill2.cardType "MONTHLY"
Check "monthly.minutes" $bill2.minutes 60

Section "A5 day pass: first 30.00 then 0.00 same day"
$r = Api POST "/api/seats/4/reserve" @{ userId = 4 }
Check "reserve.A04.code" $r.code 0
$rid3 = $r.data.id
(Api POST "/api/reservations/$rid3/checkin" @{ userId = 4 }) | Out-Null
(Api PUT "/api/clock" @{ advanceMinutes = 30 }) | Out-Null
$bill3 = (Api POST "/api/reservations/$rid3/checkout" @{ userId = 4 }).data
Check "daypass.cardType" $bill3.cardType "DAY"
Check "daypass.kind" $bill3.kind "DAY_CARD"
Check "daypass.firstAmount" $bill3.amount "30.00"
Check "daypass.minutes" $bill3.minutes 30
$r = Api POST "/api/seats/4/reserve" @{ userId = 4 }
Check "daypass.second.code" $r.code 0
$rid4 = $r.data.id
(Api POST "/api/reservations/$rid4/checkin" @{ userId = 4 }) | Out-Null
(Api PUT "/api/clock" @{ advanceMinutes = 20 }) | Out-Null
$bill4 = (Api POST "/api/reservations/$rid4/checkout" @{ userId = 4 }).data
Check "daypass.second.amount" $bill4.amount "0.00"
Check "daypass.second.minutes" $bill4.minutes 20

Section "A6 temp leave keeps seat occupied"
$r = Api POST "/api/seats/5/reserve" @{ userId = 1 }
Check "reserve.A05.code" $r.code 0
$rid5 = $r.data.id
(Api POST "/api/reservations/$rid5/checkin" @{ userId = 1 }) | Out-Null
$lv = (Api POST "/api/reservations/$rid5/leave" @{ userId = 1 }).data
Check "leave.reservation.status" $lv.status "TEMP_LEAVE"
$seat5 = (Api GET "/api/seats" $null).data | Where-Object { $_.id -eq 5 }
Check "leave.seat.leaveFlag" $seat5.leaveFlag "True"
Check "leave.seat.stillOccupied" $seat5.status "IN_USE"
Check "leave.otherCantReserve.code" (Api POST "/api/seats/5/reserve" @{ userId = 2 }).code -1
Check "endleave.status" (Api POST "/api/reservations/$rid5/end-leave" @{ userId = 1 }).data.status "IN_USE"
(Api POST "/api/reservations/$rid5/checkout" @{ userId = 1 }) | Out-Null

Section "A7 low credit cannot reserve (55 < 60)"
Check "credit55.reserve.code" (Api POST "/api/seats/6/reserve" @{ userId = 5 }).code -1

Section "A8 complaint needs a result"
$c = (Api POST "/api/complaints" @{ userId = 1; content = "Seat lamp is broken" }).data
Check "complaint.status" $c.status "PENDING"
Check "complaint.handleEmpty.code" (Api POST "/api/complaints/$($c.id)/handle" @{ handlerId = 6; result = "" }).code -1
$h = (Api POST "/api/complaints/$($c.id)/handle" @{ handlerId = 6; result = "Lamp replaced" }).data
Check "complaint.handled.status" $h.status "DONE"

Section "A9 cloud quote"
$q = (Api POST "/api/cloud/quote" @{ unitPrice = 4.00; minutes = 30 }).data
Check "quote.amount" $q.amount "2.00"
Note ("quote.source=" + $q.source)

Section "A10 dashboard consistency"
$d = (Api GET "/api/dashboard" $null).data
Check "dash.orders" $d.orders 6
Check "dash.revenue" $d.revenue "36.00"
Check "dash.avgTicket" $d.avgTicket "6.00"
Check "dash.repeatUsers" $d.repeatUsers 2

# ---------- Phase B: occupancy surge ----------
Section "B1 occupy 9 of 10"
$r = Api POST "/api/seats/10/reserve" @{ userId = 1 }
Check "reserve.A10.code" $r.code 0
$ridA = $r.data.id
Check "A10.snapshotPrice" $r.data.unitPrice "4.00"
(Api POST "/api/reservations/$ridA/checkin" @{ userId = 1 }) | Out-Null
(Api PUT "/api/clock" @{ advanceMinutes = 30 }) | Out-Null
$users = @(2, 3, 4)
$i = 0
foreach ($seat in @(1, 2, 3, 4, 6, 7, 8, 9)) {
    $uid = $users[$i % 3]
    $rr = Api POST "/api/seats/$seat/reserve" @{ userId = $uid }
    if ($rr.code -ne 0) { Check "B1.reserve.seat$seat" $rr.code 0 }
    $i++
}
$ps = (Api GET "/api/pricing/status" $null).data
Check "pricing.occupied" $ps.occupied 9
Check "pricing.total" $ps.total 10
Check "pricing.rate" $ps.occupancyRate "0.9000"
Check "pricing.shouldChange" $ps.shouldChange "True"
Check "pricing.expected" $ps.expectedPrice "4.80"

Section "B2 adjust price to 4.80 and write one record"
$adj = (Api POST "/api/pricing/adjust" @{ operatorId = 6 } $null)
Check "adjust.code" $adj.code 0
$ps2 = (Api GET "/api/pricing/status" $null).data
Check "pricing.after.current" $ps2.currentPrice "4.80"
Check "pricing.after.shouldChange" $ps2.shouldChange "False"
$changes = (Api GET "/api/pricing/changes" $null).data
Check "changes.count" @($changes).Count 1

Section "B3 usage started before the surge still pays 4.00"
$billA = (Api POST "/api/reservations/$ridA/checkout" @{ userId = 1 }).data
Check "miduse.minutes" $billA.minutes 30
Check "miduse.unitPrice" $billA.unitPrice "4.00"
Check "miduse.amount" $billA.amount "2.00"

Section "B4 new usage after the surge takes 4.80"
$r = Api POST "/api/seats/10/reserve" @{ userId = 2 }
Check "newuse.code" $r.code 0
Check "newuse.unitPrice" $r.data.unitPrice "4.80"

Section "B5 export csv"
try {
    $csv = Invoke-WebRequest -Uri "$Base/api/pricing/changes/export" -UseBasicParsing -TimeoutSec 20
    Check "export.status" $csv.StatusCode 200
    $text = $csv.Content
    Check "export.headerFields" (($text -split "`r?`n")[0].Split(",").Count) 8
    Check "export.hasSurgeRow" ($text -like "*,9,10,90%,4.00,4.80,*") "True"
} catch {
    Check "export.status" $_.Exception.Message 200
}

Section "B6 final dashboard"
$d2 = (Api GET "/api/dashboard" $null).data
Note ("orders=" + $d2.orders + " revenue=" + $d2.revenue + " avgTicket=" + $d2.avgTicket + " repeatUsers=" + $d2.repeatUsers + " occupied=" + $d2.occupied + "/" + $d2.total + " rate=" + $d2.occupancyRate + " price=" + $d2.currentPrice)

$script:lines.Add("")
$script:lines.Add("SUMMARY pass=$script:pass fail=$script:fail")
$script:lines | ForEach-Object { Write-Output $_ }
