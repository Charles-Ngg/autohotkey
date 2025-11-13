#Requires AutoHotkey v2.0
#SingleInstance Force

; ================== Settings ==================
StartDirection := "follow"           ; "follow" = use last flick direction, or "down"/"up" to force one direction
StepIntervals := [100, 20, 5, 1]   ; ms between auto wheel ticks (slower -> faster)
TripleWindow  := 100                 ; ms window to detect 3 fast wheel notches
MouseMovePoll := 25                  ; ms for mouse-move polling while auto-scroll is active
MouseMoveTolerance := 50   ; pixels allowed before auto-scroll stops
; ==============================================

; State
global gIsAuto := false
global gAutoDir := ""           ; "up" / "down"
global gStepIndex := 1
global gTimesUp := []
global gTimesDown := []
global gMouseLastX := 0, gMouseLastY := 0

; Hotkeys: "~" lets your normal scroll go through; "$" prevents our own Send() from retriggering the hotkey
~$WheelUp::HandleWheel("up")
~$WheelDown::HandleWheel("down")

; Stop on any mouse click (down event is enough)
~LButton::OnUserActivity("LButton")
~RButton::OnUserActivity("RButton")
~MButton::OnUserActivity("MButton")
~XButton1::OnUserActivity("XButton1")
~XButton2::OnUserActivity("XButton2")

; Catch-all keyboard hooks (vk08..vkFE)
SetupKeyboardActivityHooks() {
    start := 0x08, finish := 0xFE
    Loop finish - start + 1 {
        vk := start + A_Index - 1
        name := "*~$" Format("vk{:02X}", vk)
        try Hotkey(name, OnKeyboardAny, "On")
    }
}

OnKeyboardAny(*) {
    OnUserActivity("Keyboard")
}

HandleWheel(dir) {
    global gIsAuto, gAutoDir, gStepIndex, gTimesUp, gTimesDown, StepIntervals, TripleWindow, StartDirection

    now := A_TickCount

    ; While auto-scroll is running:
    if (gIsAuto) {
        if (dir != gAutoDir) {
            ; Opposite flick stops auto-scroll immediately
            StopAutoScroll("OppositeScroll")
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
    global gIsAuto, gAutoDir, gStepIndex, StepIntervals, StartDirection, gTimesUp, gTimesDown, gMouseLastX, gMouseLastY, MouseMovePoll

    gIsAuto := true
    gStepIndex := 1
    gAutoDir := (StartDirection = "follow") ? dir : StartDirection
    SetTimer(AutoScrollTick, StepIntervals[gStepIndex])

    ; Start mouse-move monitoring
    MouseGetPos &mx, &my
    gMouseLastX := mx, gMouseLastY := my
    SetTimer(MonitorMouseMove, MouseMovePoll)

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

StopAutoScroll(reason := "") {
    global gIsAuto, gAutoDir, gStepIndex, gTimesUp, gTimesDown
    gIsAuto := false
    gAutoDir := ""
    gStepIndex := 1
    SetTimer(AutoScrollTick, 0)
    SetTimer(MonitorMouseMove, 0)
    gTimesUp := []
    gTimesDown := []
    ; ToolTip(reason)  ; uncomment for debugging
}

AutoScrollTick() {
    global gIsAuto, gAutoDir
    if (!gIsAuto)
        return
    Send(gAutoDir = "up" ? "{WheelUp}" : "{WheelDown}")
}

MonitorMouseMove() {
    global gIsAuto, gMouseLastX, gMouseLastY, MouseMoveTolerance
    if (!gIsAuto) {
        SetTimer(MonitorMouseMove, 0)
        return
    }
    MouseGetPos &x, &y
    dx := x - gMouseLastX
    dy := y - gMouseLastY
    ; Use squared distance to avoid sqrt
    if ((dx*dx + dy*dy) > MouseMoveTolerance * MouseMoveTolerance) {
        StopAutoScroll("MouseMove")
        return
    }

    ; If you prefer to allow unlimited micro-drift (never stop unless a single jump exceeds tolerance),
    ; uncomment the next two lines to continually “follow” the cursor within the tolerance:
    ; gMouseLastX := x
    ; gMouseLastY := y
}

OnUserActivity(reason := "") {
    global gIsAuto
    if (gIsAuto)
        StopAutoScroll(reason)
}

; Initialize catch-all keyboard hooks at startup
SetupKeyboardActivityHooks()