#Requires AutoHotkey v2.0
#SingleInstance Force

; ================== Settings ==================
StartDirection := "follow"           ; "follow" = use last flick direction, or "down"/"up"
StepIntervals := [250, 50, 15, 5]    ; ms between ticks (slower -> faster)
ScrollMultiplier := [1, 1, 2, 5]     ; scroll events per tick
TripleWindow  := 100                 ; ms to detect 3 fast flicks
MouseMovePoll := 25                  ; ms for mouse polling
MouseMoveTolerance := 50             ; pixels allowed before stop

; ===== Speed-Up Control Settings =====
SpeedUpWindow := 300                 ; ms window to detect speed-up flicks
SpeedUpThreshold := 3                ; flicks needed to speed up
SpeedUpCooldown := 200               ; ms wait before next upgrade
; ==============================================

; Initialize Hooks
SetupKeyboardActivityHooks()

; State
global gIsAuto := false
global gAutoDir := ""
global gStepIndex := 1
global gTimesUp := []
global gTimesDown := []
global gMouseLastX := 0, gMouseLastY := 0
global gSpeedUpTimes := []
global gLastSpeedUpTime := 0

; ================== Hotkeys ==================
~$WheelUp::HandleWheel("up")
~$WheelDown::HandleWheel("down")

; Stop triggers
~LButton::OnUserActivity("LButton")
~RButton::OnUserActivity("RButton")
~MButton::OnUserActivity("MButton")
~XButton1::OnUserActivity("XButton1")
~XButton2::OnUserActivity("XButton2")

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

; ================== Logic ==================

HandleWheel(dir) {
    global gIsAuto, gAutoDir, gTimesUp, gTimesDown, TripleWindow, SpeedUpCooldown, gLastSpeedUpTime
    global gSpeedUpTimes, SpeedUpWindow, SpeedUpThreshold

    now := A_TickCount

    ; 1. If Auto-Scroll is ACTIVE
    if (gIsAuto) {
        if (dir != gAutoDir) {
            StopAutoScroll("OppositeScroll")
        } else {
            ; Speed up logic
            if (now - gLastSpeedUpTime < SpeedUpCooldown)
                return
            
            while (gSpeedUpTimes.Length && now - gSpeedUpTimes[1] > SpeedUpWindow)
                gSpeedUpTimes.RemoveAt(1)
            
            gSpeedUpTimes.Push(now)
            
            if (gSpeedUpTimes.Length >= SpeedUpThreshold) {
                IncreaseSpeed()
                gSpeedUpTimes := []
                gLastSpeedUpTime := now
            }
        }
        return
    }

    ; 2. If Auto-Scroll is INACTIVE (Detection)
    times := (dir = "up") ? gTimesUp : gTimesDown

    while (times.Length && now - times[1] > TripleWindow)
        times.RemoveAt(1)

    times.Push(now)

    if (dir = "up")
        gTimesUp := times
    else
        gTimesDown := times

    if (times.Length >= 3)
        StartAutoScroll(dir)
}

StartAutoScroll(dir) {
    global gIsAuto, gAutoDir, gStepIndex, StepIntervals, StartDirection
    global gTimesUp, gTimesDown, gMouseLastX, gMouseLastY, MouseMovePoll
    global gSpeedUpTimes, gLastSpeedUpTime

    gIsAuto := true
    gStepIndex := 1
    gAutoDir := (StartDirection = "follow") ? dir : StartDirection
    SetTimer(AutoScrollTick, StepIntervals[gStepIndex])

    MouseGetPos &mx, &my
    gMouseLastX := mx, gMouseLastY := my
    SetTimer(MonitorMouseMove, MouseMovePoll)

    ; Reset counters
    gTimesUp := []
    gTimesDown := []
    gSpeedUpTimes := []
    gLastSpeedUpTime := 0
    
    ShowSpeedIndicator()
}

IncreaseSpeed() {
    global gStepIndex, StepIntervals
    if (gStepIndex < StepIntervals.Length) {
        gStepIndex += 1
        SetTimer(AutoScrollTick, StepIntervals[gStepIndex])
        ShowSpeedIndicator()
    }
}

StopAutoScroll(reason := "") {
    global gIsAuto, gAutoDir, gStepIndex, gTimesUp, gTimesDown, gSpeedUpTimes, gLastSpeedUpTime
    
    gIsAuto := false
    gAutoDir := ""
    gStepIndex := 1
    SetTimer(AutoScrollTick, 0)
    SetTimer(MonitorMouseMove, 0)
    gTimesUp := []
    gTimesDown := []
    gSpeedUpTimes := []
    gLastSpeedUpTime := 0
    
    ScrollOSD.Hide() ; Turn off the fancy UI
}

AutoScrollTick() {
    global gIsAuto, gAutoDir, gStepIndex, ScrollMultiplier
    if (!gIsAuto)
        return
    
    mult := (gStepIndex <= ScrollMultiplier.Length) ? ScrollMultiplier[gStepIndex] : 1
    scrollKey := (gAutoDir = "up") ? "{WheelUp}" : "{WheelDown}"
    
    Loop mult {
        Send(scrollKey)
    }
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
    if ((dx*dx + dy*dy) > MouseMoveTolerance * MouseMoveTolerance) {
        StopAutoScroll("MouseMove")
        return
    }
}

OnUserActivity(reason := "") {
    global gIsAuto
    if (gIsAuto)
        StopAutoScroll(reason)
}

; ================== Fancy UI ==================

ShowSpeedIndicator() {
    global gStepIndex, gAutoDir, StepIntervals
    ScrollOSD.Show(gStepIndex, StepIntervals.Length, gAutoDir)
    SetTimer(() => ScrollOSD.Hide(), -2000) ; Fade out after 2 seconds
}

class ScrollOSD {
    static GuiObj := ""
    static TxtArrow := "", TxtLabel := "", Progress := ""
    
    static Show(level, maxLevels, dir) {
        if !this.GuiObj {
            this.Create()
        }
        
        ; Calculate Percentage
        pct := (level / maxLevels) * 100
        
        ; Dynamic Colors based on speed
        ; Level 1: Green, 2: Cyan, 3: Orange, 4: Red
        barColor := (level = 1) ? "00FF00" : (level = 2) ? "00FFFF" : (level = 3) ? "FFAA00" : "FF3333"
        arrowSymbol := (dir = "up") ? "▲" : "▼"
        labels := ["Slow", "Medium", "Fast", "TURBO"]
        txt := (level <= labels.Length) ? labels[level] : "Lvl " level

        ; Update Controls
        this.TxtArrow.Text := arrowSymbol
        this.TxtLabel.Text := txt
        this.Progress.Opt("c" barColor)
        this.Progress.Value := pct
        
        ; Show without activating (NoActivate) to keep focus on browser/doc
        ; Position: Top Center (y100)
        this.GuiObj.Show("NoActivate AutoSize xCenter y100")
        
        ; Optional: Ensure transparency in case it got reset
        WinSetTransparent(210, this.GuiObj.Hwnd)
    }
    
    static Hide() {
        if this.GuiObj
            this.GuiObj.Hide()
    }
    
    static Create() {
        ; Create a borderless, always-on-top tool window
        this.GuiObj := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20") ; E0x20 = Clickthrough
        this.GuiObj.BackColor := "1A1A1A" ; Dark Grey background
        
        ; Big Arrow
        this.TxtArrow := this.GuiObj.Add("Text", "w250 Center cWhite", "▲")
        
        ; Speed Label
        this.TxtLabel := this.GuiObj.Add("Text", "wp Center cWhite y+0", "Speed")
        
        ; Progress Bar (Slim)
        this.Progress := this.GuiObj.Add("Progress", "wp h6 c00FF00 Background333333 y+10", 0)
        
        ; Final Margin
        this.GuiObj.Add("Text", "h5", "") 
    }
}