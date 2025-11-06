#Requires AutoHotkey v2.0
#SingleInstance Force

; ================== Settings ==================
StartDirection := "follow"           ; "follow" = use last flick direction, or "down"/"up" to force one direction
StepIntervals := [200, 20, 5, 1]   ; ms between auto wheel ticks (slower -> faster)
TripleWindow  := 40                 ; ms window to detect 3 fast wheel notches
; ==============================================

; State
global gIsAuto := false
global gAutoDir := ""           ; "up" / "down"
global gStepIndex := 1
global gTimesUp := []
global gTimesDown := []

; Hotkeys: "~" lets your normal scroll go through; "$" prevents our own Send() from retriggering the hotkey
~$WheelUp::HandleWheel("up")
~$WheelDown::HandleWheel("down")

HandleWheel(dir) {
    global gIsAuto, gAutoDir, gStepIndex, gTimesUp, gTimesDown, StepIntervals, TripleWindow, StartDirection

    now := A_TickCount

    ; While auto-scroll is running:
    if (gIsAuto) {
        if (dir != gAutoDir) {
            ; Opposite flick stops auto-scroll immediately
            StopAutoScroll()
        } else {
            ; Same-direction flick increases speed (up to fastest step)
            IncreaseSpeed()
        }
        return
    }

    ; Not auto-scrolling: track fast triples per direction
    times := (dir = "up") ? gTimesUp : gTimesDown

    ; Drop entries older than the TripleWindow
    while (times.Length && now - times[1] > TripleWindow)
        times.RemoveAt(1)

    times.Push(now)

    if (dir = "up")
        gTimesUp := times
    else
        gTimesDown := times

    ; 3 flicks within window => start auto-scroll
    if (times.Length >= 3)
        StartAutoScroll(dir)
}

StartAutoScroll(dir) {
    global gIsAuto, gAutoDir, gStepIndex, StepIntervals, StartDirection, gTimesUp, gTimesDown

    gIsAuto := true
    gStepIndex := 1
    gAutoDir := (StartDirection = "follow") ? dir : StartDirection
    SetTimer(AutoScrollTick, StepIntervals[gStepIndex])

    ; Reset counters so they don't immediately retrigger
    gTimesUp := []
    gTimesDown := []
}

IncreaseSpeed() {
    global gStepIndex, StepIntervals
    if (gStepIndex < StepIntervals.Length) {
        gStepIndex += 1
        SetTimer(AutoScrollTick, StepIntervals[gStepIndex])
    }
}

StopAutoScroll() {
    global gIsAuto, gAutoDir, gStepIndex, gTimesUp, gTimesDown
    gIsAuto := false
    gAutoDir := ""
    gStepIndex := 1
    SetTimer(AutoScrollTick, 0)
    gTimesUp := []
    gTimesDown := []
}

AutoScrollTick() {
    global gIsAuto, gAutoDir
    if (!gIsAuto)
        return
    Send(gAutoDir = "up" ? "{WheelUp}" : "{WheelDown}")
}