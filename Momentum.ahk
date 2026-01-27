#Requires AutoHotkey v2.0
#SingleInstance Force

; ================== Momentum Physics Settings ==================
global Friction := 0.94              ; Velocity decay per tick (0.85=fast stop, 0.98=long coast)
global ImpulseStrength := 2.0        ; Velocity boost per scroll event
global MaxVelocity := 80.0           ; Velocity cap
global MinVelocity := 0.3            ; Stop when velocity drops below this
global TickInterval := 12            ; Physics update rate in ms (~83fps)
global ScrollSensitivity := 0.12     ; Converts velocity to scroll units

; ================== Behavior Settings ==================
global ReverseMultiplier := 2.0      ; Braking power when scrolling opposite direction
global MouseMoveTolerance := 60      ; Pixels of mouse movement before stopping
global VelocityBoostCurve := true    ; Faster flicks = more momentum added
global ShowOSD := true               ; Show visual feedback

; ================== State Variables ==================
global gVelocity := 0.0
global gAccumulator := 0.0
global gIsScrolling := false
global gMouseLastX := 0, gMouseLastY := 0
global gLastWheelTime := 0

; Initialize keyboard hooks
SetupKeyboardActivityHooks()

; Initialize OSD
MomentumOSD.Init()

; ================== Hotkeys ==================
~$WheelUp::HandleWheel(-1)
~$WheelDown::HandleWheel(1)

; Stop triggers (mouse buttons)
~LButton::OnUserActivity()
~RButton::OnUserActivity()
~MButton::OnUserActivity()
~XButton1::OnUserActivity()
~XButton2::OnUserActivity()

SetupKeyboardActivityHooks() {
    Loop 0xFE - 0x08 + 1 {
        vk := 0x08 + A_Index - 1
        try Hotkey("*~$" Format("vk{:02X}", vk), OnKeyboardAny, "On")
    }
}

OnKeyboardAny(*) {
    OnUserActivity()
}

; ================== Core Physics ==================

HandleWheel(direction) {
    global gVelocity, gIsScrolling, gMouseLastX, gMouseLastY, gLastWheelTime
    global ImpulseStrength, MaxVelocity, ReverseMultiplier, VelocityBoostCurve
    
    now := A_TickCount
    timeSinceLast := now - gLastWheelTime
    gLastWheelTime := now
    
    ; Calculate impulse with optional velocity curve
    impulse := ImpulseStrength
    
    if (VelocityBoostCurve && timeSinceLast < 150) {
        ; Faster flicking = more boost (mobile-style rapid flick detection)
        boostFactor := 1.0 + (150 - timeSinceLast) / 150  ; 1.0 to 2.0
        impulse *= boostFactor
    }
    
    impulse *= direction
    
    ; Handle direction conflicts
    if (gVelocity != 0) {
        sameDirection := (direction > 0 && gVelocity > 0) || (direction < 0 && gVelocity < 0)
        if (!sameDirection) {
            ; Opposite direction: strong braking + reverse
            impulse *= ReverseMultiplier
        }
    }
    
    ; Add momentum
    gVelocity += impulse
    
    ; Clamp velocity
    gVelocity := Max(-MaxVelocity, Min(MaxVelocity, gVelocity))
    
    ; Start physics loop if needed
    if (!gIsScrolling) {
        StartScrolling()
    }
    
    if (ShowOSD)
        UpdateOSD()
}

StartScrolling() {
    global gIsScrolling, gMouseLastX, gMouseLastY, TickInterval
    
    gIsScrolling := true
    
    ; Store mouse position for move detection
    MouseGetPos(&mx, &my)
    gMouseLastX := mx
    gMouseLastY := my
    
    ; Start timers
    SetTimer(PhysicsTick, TickInterval)
    SetTimer(MonitorMouseMove, 20)
}

PhysicsTick() {
    global gVelocity, gAccumulator, gIsScrolling
    global Friction, MinVelocity, ScrollSensitivity, ShowOSD
    
    if (!gIsScrolling)
        return
    
    ; Accumulate sub-pixel scroll amounts
    gAccumulator += gVelocity * ScrollSensitivity
    
    ; Send discrete scroll events
    while (Abs(gAccumulator) >= 1.0) {
        if (gAccumulator > 0) {
            SendInput("{WheelDown}")
            gAccumulator -= 1.0
        } else {
            SendInput("{WheelUp}")
            gAccumulator += 1.0
        }
    }
    
    ; Apply friction (exponential decay)
    gVelocity *= Friction
    
    ; Stop if momentum depleted
    if (Abs(gVelocity) < MinVelocity) {
        StopScrolling("momentum_depleted")
        return
    }
    
    if (ShowOSD)
        UpdateOSD()
}

MonitorMouseMove() {
    global gIsScrolling, gMouseLastX, gMouseLastY, MouseMoveTolerance
    
    if (!gIsScrolling) {
        SetTimer(MonitorMouseMove, 0)
        return
    }
    
    MouseGetPos(&x, &y)
    dist := Sqrt((x - gMouseLastX)**2 + (y - gMouseLastY)**2)
    
    if (dist > MouseMoveTolerance) {
        StopScrolling("mouse_moved")
    }
}

StopScrolling(reason := "") {
    global gVelocity, gAccumulator, gIsScrolling
    
    gVelocity := 0.0
    gAccumulator := 0.0
    gIsScrolling := false
    
    SetTimer(PhysicsTick, 0)
    SetTimer(MonitorMouseMove, 0)
    
    MomentumOSD.Hide()
}

OnUserActivity(*) {
    global gIsScrolling
    if (gIsScrolling)
        StopScrolling("user_input")
}

UpdateOSD() {
    global gVelocity, MaxVelocity
    MomentumOSD.Show(gVelocity, MaxVelocity)
}

; ================== Visual Feedback ==================

class MomentumOSD {
    static myGui := ""
    static Arrow := ""
    static VelocityText := ""
    static VelocityBar := ""
    static IsCreated := false
    
    static Init() {
        this.Create()
    }
    
    static Show(velocity, maxVel) {
        if (!this.IsCreated)
            this.Create()
        
        absVel := Abs(velocity)
        pct := Min(100, (absVel / maxVel) * 100)
        dir := velocity > 0 ? "down" : "up"
        
        ; Dynamic color gradient: Green → Cyan → Orange → Red
        if (pct < 25) {
            color := "4CAF50"      ; Green
        } else if (pct < 50) {
            color := "00BCD4"      ; Cyan
        } else if (pct < 75) {
            color := "FF9800"      ; Orange
        } else {
            color := "FF5252"      ; Red
        }
        
        ; Update arrow direction
        arrowChar := (dir = "up") ? "▲" : "▼"
        this.Arrow.Value := arrowChar
        this.Arrow.SetFont("c" color)
        
        ; Update velocity display
        this.VelocityText.Value := Format("{:.0f}%", pct)
        this.VelocityText.SetFont("c" color)
        
        ; Update progress bar
        this.VelocityBar.Opt("c" color)
        this.VelocityBar.Value := Round(pct)
        
        ; Show window
        this.myGui.Show("NoActivate AutoSize xCenter y80")
        try WinSetTransparent(220, this.myGui.Hwnd)
        
        ; Auto-hide timer
        SetTimer(OSDHideCallback, -1500)
    }
    
    static Hide() {
        if (this.myGui && this.IsCreated)
            this.myGui.Hide()
    }
    
    static Create() {
        if (this.IsCreated)
            return
            
        ; Sleek borderless window
        this.myGui := Gui("+AlwaysOnTop -Caption +ToolWindow +E0x20")
        this.myGui.BackColor := "121212"
        this.myGui.MarginX := 20
        this.myGui.MarginY := 15
        
        ; Large direction arrow
        this.myGui.SetFont("s32 bold c4CAF50", "Segoe UI Symbol")
        this.Arrow := this.myGui.Add("Text", "w180 Center vArrow", "▼")
        
        ; Velocity percentage
        this.myGui.SetFont("s14 c888888", "Segoe UI")
        this.VelocityText := this.myGui.Add("Text", "wp Center vVelocityText y+2", "0%")
        
        ; Momentum bar
        this.VelocityBar := this.myGui.Add("Progress", "wp h6 c4CAF50 Background2A2A2A Range0-100 vVelocityBar y+12", 0)
        
        ; Label
        this.myGui.SetFont("s9 c555555", "Segoe UI")
        this.myGui.Add("Text", "wp Center y+8", "MOMENTUM")
        
        this.IsCreated := true
    }
}

; Callback function for hiding OSD
OSDHideCallback() {
    MomentumOSD.Hide()
}