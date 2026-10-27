#Requires AutoHotkey v2.0
#SingleInstance Force
; ============================================================
;  拖放收纳板  DropBoard  (AutoHotkey v2 / GDI 自绘)
;  拖入 文件夹 / 文件 / 网址 → 自动分流到三个标签页
;  单击卡片打开（已打开则激活），右键重命名 / 删除 / 复制路径
;  配置：同目录 DropBoard.json
; ============================================================

; 声明 Per-Monitor V2 DPI 感知，避免窗口内容被系统拉伸、保证高清渲染
try DllCall("user32\SetProcessDpiAwarenessContext", "ptr", -4)

Bgr(c) => ((c & 0xFF) << 16) | (c & 0xFF00) | ((c >> 16) & 0xFF)
Qt(s) => Chr(34) s Chr(34)

class DropBoard {
    static W := 480
    static H := 636
    static CW := 116        ; 收起后的宽度（只露出「收纳盒」三个字）
    static CH := 46         ; 收起后的高度 = 标题栏高度
    static MAX := 10
    static CFG := A_ScriptDir "\DropBoard.json"

    static TABS := [
        {key: "folder", name: "文件夹", hint: "把文件夹拖到这里", sub: "窗口任意位置都可以放下",
         accent: 0x5B6CF0, card: 0x20243A, hover: 0x2C3252, fg: 0xDDE3FF},
        {key: "file",   name: "文件",   hint: "把文件拖到这里",   sub: "支持一次拖入多个",
         accent: 0x19B39E, card: 0x162E2C, hover: 0x204642, fg: 0xD6F5F0},
        {key: "url",    name: "网址",   hint: "复制链接后点「+ 粘贴网址」", sub: "也可在标题栏右键里手动输入",
         accent: 0xE0713F, card: 0x33251E, hover: 0x4A3329, fg: 0xFFE3D4}
    ]

    __New() {
        this.s := A_ScreenDPI / 96
        this.tabIdx := 1
        this.items := {folder: [], file: [], url: []}
        this.hoverTab := 0
        this.hoverCard := 0
        this.hoverClose := false
        this.msg := ""
        this.msgClr := 0x9AA3B5
        this.msgTimer := 0
        this.opened := Map()
        this.pos := {x: "", y: ""}
        this.collapsed := false
        this.topmost := true
        this.drag := false
        this.dragMoved := false
        this.lastTitleClick := 0
        this.dragOrigin := {cx: 0, cy: 0, wx: 0, wy: 0}
        this.hoverPaste := false
        this.LoadCfg()
        this.Build()
    }

    Build() {
        w := this.P(this.collapsed ? DropBoard.CW : DropBoard.W)
        h := this.P(this.collapsed ? DropBoard.CH : DropBoard.H)
        g := Gui("-Caption -DPIScale" (this.topmost ? " +AlwaysOnTop" : ""), "拖放收纳板")
        g.BackColor := "15171C"
        g.Show("w" w " h" h (this.pos.x = "" ? " Center" : " x" this.pos.x " y" this.pos.y))
        this.gui := g
        this.hwnd := g.Hwnd
        this.pw := w
        this.ph := h
        this.SetIcon()

        try DllCall("dwmapi\DwmSetWindowAttribute", "ptr", this.hwnd, "int", 33, "int*", 2, "int", 4)

        hdcS := DllCall("user32\GetDC", "ptr", this.hwnd, "ptr")
        this.memDC := DllCall("gdi32\CreateCompatibleDC", "ptr", hdcS, "ptr")
        this.memBmp := DllCall("gdi32\CreateCompatibleBitmap", "ptr", hdcS, "int", w, "int", h, "ptr")
        this.oldBmp := DllCall("gdi32\SelectObject", "ptr", this.memDC, "ptr", this.memBmp, "ptr")
        DllCall("user32\ReleaseDC", "ptr", this.hwnd, "ptr", hdcS)

        this.fTitle := this.MkFont(13, true)
        this.fTab := this.MkFont(10.5, true)
        this.fCard := this.MkFont(12, true)
        this.fSmall := this.MkFont(8.5, false)
        this.fStatus := this.MkFont(9, false)
        this.fEmpty := this.MkFont(13, true)
        this.fEmptySub := this.MkFont(9.5, false)

        DllCall("shell32\DragAcceptFiles", "ptr", this.hwnd, "int", 1)

        OnMessage(0x000F, ObjBindMethod(this, "WM_PAINT"))
        OnMessage(0x0014, ObjBindMethod(this, "WM_ERASEBKGND"))
        OnMessage(0x0200, ObjBindMethod(this, "WM_MOUSEMOVE"))
        OnMessage(0x0201, ObjBindMethod(this, "WM_LBUTTONDOWN"))
        OnMessage(0x0203, ObjBindMethod(this, "WM_LBUTTONDBLCLK"))
        OnMessage(0x0202, ObjBindMethod(this, "WM_LBUTTONUP"))
        OnMessage(0x0205, ObjBindMethod(this, "WM_RBUTTONUP"))
        OnMessage(0x02A3, ObjBindMethod(this, "WM_MOUSELEAVE"))
        OnMessage(0x0233, ObjBindMethod(this, "WM_DROPFILES"))
        OnExit((*) => this.SaveCfg())

        this.Paint()
    }

    P(v) => Round(v * this.s)

    ; ---- 图标：托盘 + 窗口（任务栏 / Alt+Tab）----
    ; 只依赖同目录 DropBoard.ico，缺失时静默跳过，不影响主流程
    SetIcon() {
        ico := A_ScriptDir "\DropBoard.ico"
        if !FileExist(ico)
            return
        try TraySetIcon(ico)
        A_IconTip := "拖放收纳板"
        ; ICON_SMALL(0) 用 16px，ICON_BIG(1) 用 48px 应对 200% 缩放
        for id in [0, 1] {
            h := DllCall("user32\LoadImage", "ptr", 0, "str", ico, "uint", 1
                , "int", (id ? 48 : 16), "int", (id ? 48 : 16)
                , "uint", 0x8010, "ptr")            ; LR_LOADFROMFILE | LR_SHARED
            if h
                DllCall("user32\SendMessage", "ptr", this.hwnd, "uint", 0x0080
                    , "ptr", id, "ptr", h)          ; WM_SETICON
        }
    }

    ; ---- 收起 / 展开 ----
    ToggleCollapse() {
        this.collapsed := !this.collapsed
        this.drag := false
        try DllCall("user32\ReleaseCapture")
        this.hoverTab := 0
        this.hoverCard := 0
        this.hoverClose := false
        this.hoverPaste := false
        if (this.msgTimer) {
            SetTimer(this.msgTimer, 0)
            this.msgTimer := 0
        }
        this.msg := ""
        this.ResizeTo(this.P(this.collapsed ? DropBoard.CW : DropBoard.W)
            , this.P(this.collapsed ? DropBoard.CH : DropBoard.H))
        this.SaveCfg()
    }

    ; 换尺寸：重建内存位图，保持窗口左上角不动
    ResizeTo(w, h) {
        hdcS := DllCall("user32\GetDC", "ptr", this.hwnd, "ptr")
        newDC := DllCall("gdi32\CreateCompatibleDC", "ptr", hdcS, "ptr")
        newBmp := DllCall("gdi32\CreateCompatibleBitmap", "ptr", hdcS, "int", w, "int", h, "ptr")
        newOld := DllCall("gdi32\SelectObject", "ptr", newDC, "ptr", newBmp, "ptr")
        DllCall("user32\ReleaseDC", "ptr", this.hwnd, "ptr", hdcS)
        if (this.memDC) {
            DllCall("gdi32\SelectObject", "ptr", this.memDC, "ptr", this.oldBmp, "ptr")
            DllCall("gdi32\DeleteObject", "ptr", this.memBmp)
            DllCall("gdi32\DeleteDC", "ptr", this.memDC)
        }
        this.memDC := newDC
        this.memBmp := newBmp
        this.oldBmp := newOld
        this.pw := w
        this.ph := h
        WinGetPos(&wx, &wy, , , "ahk_id " this.hwnd)
        WinMove(wx, wy, w, h, "ahk_id " this.hwnd)
        this.Paint()
    }

    ToggleTop() {
        this.topmost := !this.topmost
        try WinSetAlwaysOnTop(this.topmost ? 1 : 0, "ahk_id " this.hwnd)
        this.SaveCfg()
        this.Paint()
    }

    TitleMenu() {
        m := Menu()
        m.Add(this.collapsed ? "展开窗口" : "收起为「收纳盒」", (*) => this.ToggleCollapse())
        m.Add("窗口置顶", (*) => this.ToggleTop())
        if (this.topmost)
            m.Check("窗口置顶")
        m.Add()
        m.Add("粘贴网址（剪贴板）", (*) => this.PasteUrl(true))
        m.Add("手动输入网址…", (*) => this.PasteUrl(false))
        m.Add()
        m.Add("退出", (*) => this.Quit())
        m.Show()
    }

    MkFont(pt, bold) {
        h := -Round(pt * A_ScreenDPI / 72)
        return DllCall("gdi32\CreateFontW", "int", h, "int", 0, "int", 0, "int", 0
            , "int", bold ? 700 : 400, "uint", 0, "uint", 0, "uint", 0, "uint", 1
            , "uint", 0, "uint", 0, "uint", 5, "uint", 0, "wstr", "Microsoft YaHei UI", "ptr")
    }

    Fill(hdc, x, y, w, h, rgb) {
        rc := Buffer(16, 0)
        NumPut("int", x, "int", y, "int", x + w, "int", y + h, rc)
        br := DllCall("gdi32\CreateSolidBrush", "uint", Bgr(rgb), "ptr")
        DllCall("user32\FillRect", "ptr", hdc, "ptr", rc, "ptr", br)
        DllCall("gdi32\DeleteObject", "ptr", br)
    }

    Tx(hdc, txt, x, y, w, h, rgb, font, flags) {
        rc := Buffer(16, 0)
        NumPut("int", x, "int", y, "int", x + w, "int", y + h, rc)
        DllCall("gdi32\SelectObject", "ptr", hdc, "ptr", font, "ptr")
        DllCall("gdi32\SetTextColor", "ptr", hdc, "uint", Bgr(rgb))
        DllCall("gdi32\SetBkMode", "ptr", hdc, "int", 1)
        DllCall("user32\DrawTextW", "ptr", hdc, "wstr", txt, "int", -1, "ptr", rc, "uint", flags)
    }

    Paint() {
        this.Render()
        hdc := DllCall("user32\GetDC", "ptr", this.hwnd, "ptr")
        DllCall("gdi32\BitBlt", "ptr", hdc, "int", 0, "int", 0, "int", this.pw, "int", this.ph
            , "ptr", this.memDC, "int", 0, "int", 0, "uint", 0x00CC0020)
        DllCall("user32\ReleaseDC", "ptr", this.hwnd, "ptr", hdc)
    }

    Render() {
        hdc := this.memDC
        P := (v) => Round(v * this.s)
        W := this.pw
        H := this.ph

        if (this.collapsed) {
            this.RenderBadge(hdc, P, W, H)
            return
        }

        tabs := DropBoard.TABS
        cur := tabs[this.tabIdx]
        curKey := cur.key
        list := this.items.%curKey%

        this.Fill(hdc, 0, 0, W, H, 0x15171C)
        this.Fill(hdc, 0, 0, W, P(46), 0x1A1D24)
        this.Fill(hdc, 0, P(45), W, P(1), 0x2B3040)
        this.Fill(hdc, 0, 0, W, P(1), 0x2B3040)
        this.Fill(hdc, 0, H - P(1), W, P(1), 0x2B3040)
        this.Fill(hdc, 0, 0, P(1), H, 0x2B3040)
        this.Fill(hdc, W - P(1), 0, P(1), H, 0x2B3040)

        this.Tx(hdc, "拖放收纳板", P(16), 0, P(280), P(46), 0xE6E9F0, this.fTitle, 0x0020 | 0x0004 | 0x0800)

        cx := W - P(38), cy := P(8), cw := P(28), ch := P(28)
        if (this.hoverClose)
            this.Fill(hdc, cx, cy, cw, ch, 0xC0392B)
        this.Tx(hdc, "×", cx, cy, cw, ch, this.hoverClose ? 0xFFFFFF : 0x8A93A6, this.fTab, 0x0001 | 0x0004 | 0x0020)

        for i, t in tabs {
            x := P(12) + (i - 1) * P(154)
            y := P(56)
            tw := P(148), th := P(36)
            on := (i = this.tabIdx)
            hov := (this.hoverTab = i)
            bg := on ? t.accent : (hov ? 0x252A34 : 0x1C2027)
            this.Fill(hdc, x, y, tw, th, bg)
            if (on)
                this.Fill(hdc, x, y + th - P(3), tw, P(3), 0xFFFFFF)
            lk := t.key
            larr := this.items.%lk%
            cnt := larr.Length
            label := t.name "  " cnt "/" DropBoard.MAX
            this.Tx(hdc, label, x, y, tw, th, on ? 0xFFFFFF : (hov ? 0xC6CDDA : 0x7C8494), this.fTab
                , 0x0001 | 0x0004 | 0x0020 | 0x0800)
        }

        if (list.Length = 0) {
            this.Tx(hdc, cur.hint, 0, P(280), W, P(40), 0x5C6478, this.fEmpty, 0x0001 | 0x0004 | 0x0020)
            this.Tx(hdc, cur.sub, 0, P(322), W, P(28), 0x474E5E, this.fEmptySub, 0x0001 | 0x0004 | 0x0020)
        } else {
            for i, it in list {
                y := P(104) + (i - 1) * P(50)
                x := P(12)
                cw2 := P(456), chh := P(44)
                hov := (this.hoverCard = i)
                this.Fill(hdc, x, y, cw2, chh, hov ? cur.hover : cur.card)
                this.Fill(hdc, x, y, P(4), chh, cur.accent)
                this.Tx(hdc, Format("{:02}", i), x + P(12), y, P(26), chh, cur.accent, this.fSmall
                    , 0x0000 | 0x0004 | 0x0020 | 0x0800)
                this.Tx(hdc, it.name, x + P(40), y, P(266), chh, cur.fg, this.fCard
                    , 0x0000 | 0x0004 | 0x0020 | 0x8000 | 0x0800)
                this.Tx(hdc, it.sub, x + P(310), y, P(136), chh, 0x6E7686, this.fSmall
                    , 0x0002 | 0x0004 | 0x0020 | 0x8000 | 0x0800)
            }
        }

        sy := P(602)
        this.Fill(hdc, 0, sy - P(1), W, P(1), 0x2B3040)
        showPaste := (curKey = "url")
        tipW := W - P(32) - (showPaste ? P(126) : 0)
        tip := this.msg != "" ? this.msg : (cur.hint " · 共 " list.Length "/" DropBoard.MAX " 项")
        clr := this.msg != "" ? this.msgClr : 0x6E7686
        this.Tx(hdc, tip, P(16), sy, tipW, P(32), clr, this.fStatus
            , 0x0000 | 0x0004 | 0x0020 | 0x8000 | 0x0800)

        if (showPaste) {
            bx := W - P(120), by := sy + P(4), bw := P(108), bh := P(24)
            this.Fill(hdc, bx, by, bw, bh, this.hoverPaste ? cur.accent : 0x3A2A22)
            this.Tx(hdc, "+ 粘贴网址", bx, by, bw, bh
                , this.hoverPaste ? 0xFFFFFF : 0xF0B08A, this.fStatus, 0x0001 | 0x0004 | 0x0020)
        }
    }

    ; 收起态：只剩「收纳盒」三个字
    RenderBadge(hdc, P, W, H) {
        acc := this.CurrentTab().accent
        this.Fill(hdc, 0, 0, W, H, 0x1A1D24)
        this.Fill(hdc, 0, 0, W, P(1), 0x2B3040)
        this.Fill(hdc, 0, H - P(1), W, P(1), 0x2B3040)
        this.Fill(hdc, 0, 0, P(1), H, 0x2B3040)
        this.Fill(hdc, W - P(1), 0, P(1), H, 0x2B3040)
        this.Fill(hdc, 0, 0, P(3), H, acc)
        this.Tx(hdc, "收纳盒", P(3), 0, W - P(3), H, 0xE6E9F0, this.fTitle, 0x0001 | 0x0004 | 0x0020)
    }

    ; ---------- 消息 ----------
    WM_PAINT(wParam, lParam, msg, hwnd) {
        if (hwnd != this.hwnd)
            return
        ps := Buffer(A_PtrSize = 8 ? 72 : 64, 0)
        hdc := DllCall("user32\BeginPaint", "ptr", hwnd, "ptr", ps, "ptr")
        this.Render()
        DllCall("gdi32\BitBlt", "ptr", hdc, "int", 0, "int", 0, "int", this.pw, "int", this.ph
            , "ptr", this.memDC, "int", 0, "int", 0, "uint", 0x00CC0020)
        DllCall("user32\EndPaint", "ptr", hwnd, "ptr", ps)
        return 1
    }

    WM_ERASEBKGND(wParam, lParam, msg, hwnd) {
        if (hwnd = this.hwnd)
            return 1
    }

    WM_MOUSEMOVE(wParam, lParam, msg, hwnd) {
        if (hwnd != this.hwnd)
            return

        if (this.drag) {
            ; 兜底：左键其实已经松开（消息丢了）→ 结束拖动，避免窗口被鼠标到处拽
            if !GetKeyState("LButton", "P") {
                this.drag := false
                try DllCall("user32\ReleaseCapture")
                this.Paint()
                return
            }
            pt := Buffer(8, 0)
            DllCall("user32\GetCursorPos", "ptr", pt)
            cx := NumGet(pt, 0, "int"), cy := NumGet(pt, 4, "int")
            nx := this.dragOrigin.wx + (cx - this.dragOrigin.cx)
            ny := this.dragOrigin.wy + (cy - this.dragOrigin.cy)
            if (Abs(nx - this.dragOrigin.wx) > 2 || Abs(ny - this.dragOrigin.wy) > 2)
                this.dragMoved := true
            DllCall("user32\SetWindowPos", "ptr", this.hwnd, "ptr", 0, "int", nx, "int", ny
                , "int", 0, "int", 0, "uint", 0x0001 | 0x0004)
            return
        }

        x := lParam & 0xFFFF, y := (lParam >> 16) & 0xFFFF
        changed := false

        hc := (!this.collapsed && x >= this.pw - this.P(38) && x <= this.pw - this.P(10) && y >= this.P(8) && y <= this.P(36))
        if (hc != this.hoverClose) {
            this.hoverClose := hc
            changed := true
        }
        hp := (this.HitPaste(x, y) != "")
        if (hp != this.hoverPaste) {
            this.hoverPaste := hp
            changed := true
        }
        ht := this.HitTab(x, y)
        if (ht != this.hoverTab) {
            this.hoverTab := ht
            changed := true
        }
        hk := this.HitCard(x, y)
        if (hk != this.hoverCard) {
            this.hoverCard := hk
            changed := true
            if (hk > 0) {
                ck := this.CurrentTab().key
                lst := this.items.%ck%
                it := lst[hk]
                this.msg := it.target
                this.msgClr := 0x8A93A6
            } else if (this.msgTimer = 0) {
                this.msg := ""
            }
        }
        if (changed)
            this.Paint()

        me := Buffer(24, 0)
        NumPut("uint", A_PtrSize = 8 ? 24 : 20, me, 0)
        NumPut("uint", 0x00000002, me, 4)
        NumPut("ptr", this.hwnd, me, 8)
        NumPut("uint", 0, me, A_PtrSize = 8 ? 16 : 12)
        DllCall("user32\TrackMouseEvent", "ptr", me)
    }

    WM_MOUSELEAVE(wParam, lParam, msg, hwnd) {
        if (hwnd != this.hwnd)
            return
        if (this.drag)
            return
        if (this.hoverTab = 0 && this.hoverCard = 0 && !this.hoverClose && !this.hoverPaste)
            return
        this.hoverTab := 0
        this.hoverCard := 0
        this.hoverClose := false
        this.hoverPaste := false
        if (this.msgTimer = 0)
            this.msg := ""
        this.Paint()
    }

    WM_LBUTTONDOWN(wParam, lParam, msg, hwnd) {
        if (hwnd != this.hwnd)
            return
        x := lParam & 0xFFFF, y := (lParam >> 16) & 0xFFFF
        ; 标题栏（收起态则整块）→ 自己接管拖动，便于统计双击
        if (this.collapsed || (y < this.P(46) && x < this.pw - this.P(40))) {
            pt := Buffer(8, 0)
            DllCall("user32\GetCursorPos", "ptr", pt)
            WinGetPos(&wx, &wy, , , "ahk_id " this.hwnd)
            this.dragOrigin := {cx: NumGet(pt, 0, "int"), cy: NumGet(pt, 4, "int"), wx: wx, wy: wy}
            this.drag := true
            this.dragMoved := false
            DllCall("user32\SetCapture", "ptr", this.hwnd)
            return 1
        }
    }

    WM_LBUTTONDBLCLK(wParam, lParam, msg, hwnd) {
        if (hwnd != this.hwnd)
            return
        x := lParam & 0xFFFF, y := (lParam >> 16) & 0xFFFF
        ; 双击标题栏（收起态双击整块）→ 收起 / 展开
        if (this.collapsed || y < this.P(46)) {
            this.drag := false
            this.lastTitleClick := 0
            try DllCall("user32\ReleaseCapture")
            this.ToggleCollapse()
            return 1
        }
    }

    WM_LBUTTONUP(wParam, lParam, msg, hwnd) {
        if (hwnd != this.hwnd)
            return
        x := lParam & 0xFFFF, y := (lParam >> 16) & 0xFFFF

        if (this.drag) {
            this.drag := false
            DllCall("user32\ReleaseCapture")
            inTitle := this.collapsed || (y < this.P(46) && x < this.pw - this.P(40))
            if (inTitle && !this.dragMoved) {
                ; 双击标题栏 → 收起 / 展开
                if (this.lastTitleClick && (A_TickCount - this.lastTitleClick <= 400)) {
                    this.lastTitleClick := 0
                    this.ToggleCollapse()
                    return 1
                }
                this.lastTitleClick := A_TickCount
            } else {
                this.lastTitleClick := 0
            }
            this.Paint()
            return 1
        }

        if (this.collapsed)
            return

        if (y < this.P(46) && x >= this.pw - this.P(38)) {
            this.Quit()
            return 1
        }
        if (this.HitPaste(x, y) != "") {
            this.PasteUrl(true)
            return 1
        }
        t := this.HitTab(x, y)
        if (t > 0) {
            this.SwitchTab(t)
            return 1
        }
        c := this.HitCard(x, y)
        if (c > 0) {
            this.OpenIndex(c)
            return 1
        }
    }

    WM_RBUTTONUP(wParam, lParam, msg, hwnd) {
        if (hwnd != this.hwnd)
            return
        x := lParam & 0xFFFF, y := (lParam >> 16) & 0xFFFF
        if (this.collapsed || y < this.P(46)) {
            this.TitleMenu()
            return 1
        }
        c := this.HitCard(x, y)
        if (c > 0)
            this.CardMenu(c)
        return 1
    }

    WM_DROPFILES(wParam, lParam, msg, hwnd) {
        if (hwnd != this.hwnd)
            return
        hDrop := wParam
        cnt := DllCall("shell32\DragQueryFileW", "ptr", hDrop, "uint", 0xFFFFFFFF, "ptr", 0, "uint", 0)
        list := []
        Loop cnt {
            i := A_Index - 1
            len := DllCall("shell32\DragQueryFileW", "ptr", hDrop, "uint", i, "ptr", 0, "uint", 0)
            buf := Buffer((len + 1) * 2, 0)
            DllCall("shell32\DragQueryFileW", "ptr", hDrop, "uint", i, "ptr", buf, "uint", len + 1)
            list.Push(StrGet(buf, "UTF-16"))
        }
        DllCall("shell32\DragFinish", "ptr", hDrop)
        if (list.Length > 0)
            this.AddMany(list)
        try DllCall("user32\SetForegroundWindow", "ptr", this.hwnd)
        return 0
    }

    ; ---------- 命中 ----------
    HitTab(x, y) {
        if (this.collapsed)
            return 0
        if (y < this.P(56) || y > this.P(92))
            return 0
        Loop 3 {
            x0 := this.P(12) + (A_Index - 1) * this.P(154)
            if (x >= x0 && x <= x0 + this.P(148))
                return A_Index
        }
        return 0
    }

    HitCard(x, y) {
        if (this.collapsed)
            return 0
        ck := this.CurrentTab().key
        list := this.items.%ck%
        if (y < this.P(104))
            return 0
        idx := Floor((y - this.P(104)) / this.P(50)) + 1
        if (idx < 1 || idx > list.Length)
            return 0
        if (Mod(y - this.P(104), this.P(50)) > this.P(44))
            return 0
        if (x < this.P(12) || x > this.P(468))
            return 0
        return idx
    }

    ; 网址页右下角「+ 粘贴网址」按钮
    HitPaste(x, y) {
        if (this.collapsed || this.CurrentTab().key != "url")
            return ""
        bx := this.pw - this.P(120), by := this.P(606)
        if (x >= bx && x <= bx + this.P(108) && y >= by && y <= by + this.P(24))
            return "paste"
        return ""
    }

    CurrentTab() => DropBoard.TABS[this.tabIdx]

    SwitchTab(i) {
        if (i = this.tabIdx)
            return
        this.tabIdx := i
        this.hoverCard := 0
        this.msg := ""
        if (this.msgTimer) {
            SetTimer(this.msgTimer, 0)
            this.msgTimer := 0
        }
        this.Paint()
    }

    ; ---------- 手动粘贴网址（兜底入口） ----------
    PasteUrl(useClip) {
        txt := ""
        if (useClip) {
            try txt := Trim(A_Clipboard, " `t`r`n")
            if (txt != "" && this.Classify(txt) != "") {
                this.AddText(txt)
                return
            }
        }
        ; 置顶窗口会盖住输入框，先临时取消置顶
        wasTop := this.topmost
        if (wasTop)
            try WinSetAlwaysOnTop(0, "ahk_id " this.hwnd)
        ib := InputBox("粘贴或输入网址，例如 github.com 或 https://example.com/a"
            , "手动添加网址", "w600 h150", txt)
        if (wasTop)
            try WinSetAlwaysOnTop(1, "ahk_id " this.hwnd)
        if (ib.Result != "OK")
            return
        s := Trim(ib.Value, " `t`r`n")
        if (s = "")
            return
        this.AddText(s)
    }

    AddText(s) {
        info := this.Classify(s)
        if !info {
            this.Flash("无法识别：" s, 0xE0713F)
            return
        }
        if (info.type = "url" && this.tabIdx != 3)
            this.SwitchTab(3)
        this.AddMany([s])
    }

    AddMany(rawList) {
        ok := 0, dup := 0, full := 0, bad := 0
        dupNames := []
        for raw in rawList {
            r := this.AddOne(raw)
            if (r.status = "ok")
                ok += 1
            else if (r.status = "dup") {
                dup += 1
                dupNames.Push(r.name)
            } else if (r.status = "full")
                full += 1
            else
                bad += 1
        }
        txt := "", clr := 0x6FB98C
        if (ok > 0)
            txt .= "已添加 " ok " 项"
        if (dup > 0) {
            nm := dupNames.Length <= 2 ? JoinArr(dupNames, "、") : (dupNames[1] " 等 " dup " 项")
            txt .= (txt ? "；" : "") "已存在：" nm "（未重复添加）"
            clr := 0xE0B040
        }
        if (full > 0) {
            txt .= (txt ? "；" : "") "标签页已满（上限 " DropBoard.MAX " 个），拒绝 " full " 项"
            clr := 0xE0B040
        }
        if (bad > 0) {
            txt .= (txt ? "；" : "") "无法识别 " bad " 项"
            clr := 0xE0713F
        }
        if (txt = "")
            txt := "没有可添加的内容"
        this.Flash(txt, clr)
        this.Paint()
    }

    AddOne(raw) {
        info := this.Classify(raw)
        if !info
            return {status: "bad", name: raw}
        tkey := info.type
        list := this.items.%tkey%
        key := this.KeyOf(tkey, info.target)
        for it in list {
            if (this.KeyOf(tkey, it.target) = key)
                return {status: "dup", name: it.name}
        }
        if (list.Length >= DropBoard.MAX)
            return {status: "full", name: info.target}
        list.Push({name: this.NameOf(tkey, info.target), sub: this.SubOf(tkey, info.target)
            , target: info.target, added: FormatTime(A_Now, "yyyy-MM-dd HH:mm")})
        this.SaveCfg()
        return {status: "ok", name: info.target}
    }

    Classify(raw) {
        s := Trim(raw, " `t`r`n")
        if (s = "")
            return ""
        if RegExMatch(s, "i)^file:///") {
            p := SubStr(s, 9)
            p := StrReplace(p, "/", "\")
            p := UrlDecode(p)
            if DirExist(p)
                return {type: "folder", target: this.NormPath(p)}
            if FileExist(p)
                return {type: "file", target: this.NormPath(p)}
        }
        if DirExist(s)
            return {type: "folder", target: this.NormPath(s)}
        if FileExist(s)
            return {type: "file", target: this.NormPath(s)}
        if RegExMatch(s, "i)^(https?|ftp)://\S+$")
            return {type: "url", target: s}
        if RegExMatch(s, "i)^www\.\S+$")
            return {type: "url", target: "https://" s}
        if RegExMatch(s, "i)^[a-z0-9][a-z0-9\-\.]*\.[a-z]{2,}(:\d+)?([/?#]\S*)?$")
            return {type: "url", target: "https://" s}
        return ""
    }

    NormPath(p) {
        p := StrReplace(p, "/", "\")
        p := RTrim(p, "\/")
        if (StrLen(p) = 2 && SubStr(p, 2, 1) = ":")
            p .= "\"
        return p
    }

    KeyOf(type, target) {
        if (type = "url") {
            t := StrLower(target)
            t := RegExReplace(t, "^https?://", "")
            t := RTrim(t, "/")
            return "url:" t
        }
        return type ":" StrLower(RTrim(target, "\/"))
    }

    NameOf(type, target) {
        if (type = "folder") {
            SplitPath target, &nm
            if (nm = "")
                nm := target
            return nm
        }
        if (type = "file") {
            SplitPath target, &nm, , &ext, &noext
            return noext = "" ? nm : noext
        }
        return this.HostOf(target)
    }

    SubOf(type, target) {
        if (type = "folder") {
            SplitPath target, &nm, &dir
            return dir = "" ? target : RTrim(dir, "\")
        }
        if (type = "file") {
            SplitPath target, &nm, , &ext
            sz := ""
            try sz := Format("{:.1f} KB", FileGetSize(target) / 1024)
            return StrUpper(ext) "  " sz
        }
        return target
    }

    HostOf(u) {
        if RegExMatch(u, "i)^[a-z]+://([^/?#]+)", &m) {
            h := m[1]
            h := RegExReplace(h, "i)^www\.")
            h := RegExReplace(h, ":\d+$")
            return h
        }
        return u
    }

    ; ---------- 打开 ----------
    OpenIndex(idx) {
        ck := this.CurrentTab().key
        list := this.items.%ck%
        if (idx > list.Length)
            return
        this.OpenItem(list[idx], ck)
    }

    OpenItem(it, type) {
        if (type = "folder")
            this.OpenFolder(it)
        else if (type = "file")
            this.OpenFile(it)
        else if (type = "url")
            this.OpenUrl(it)
    }

    OpenFolder(it) {
        if !DirExist(it.target) {
            this.Flash("文件夹已不存在：" it.target, 0xE0713F)
            return
        }
        if (this.ActivateFolder(it.target))
            return
        try Run Qt(it.target)
        catch as e
            this.Flash("打开失败：" e.Message, 0xE0713F)
    }

    ActivateFolder(path) {
        try {
            wins := ComObject("Shell.Application").Windows
            for w in wins {
                try {
                    p := w.Document.Folder.Self.Path
                    if (p != "" && this.SamePath(p, path)) {
                        h := Integer(w.HWND)
                        if (h && WinExist("ahk_id " h)) {
                            this.ForceActivate(h)
                            return true
                        }
                    }
                }
            }
        }
        return false
    }

    SamePath(a, b) => StrLower(RTrim(a, "\/")) = StrLower(RTrim(b, "\/"))

    OpenFile(it) {
        if !FileExist(it.target) {
            this.Flash("文件已不存在：" it.target, 0xE0713F)
            return
        }
        if this.opened.Has(it.target) {
            rec := this.opened[it.target]
            if (rec.h && WinExist("ahk_id " rec.h)) {
                this.ForceActivate(rec.h)
                return
            }
        }
        SplitPath it.target, &nm, , &ext, &noext
        if (StrLen(noext) >= 3) {
            old := A_TitleMatchMode
            SetTitleMatchMode 2
            h := WinExist(noext)
            SetTitleMatchMode old
            if (h && h != this.hwnd) {
                this.ForceActivate(h)
                this.opened[it.target] := {h: h}
                return
            }
        }
        try {
            Run Qt(it.target)
            SetTimer(() => this.CaptureWindow(it.target), -900)
        } catch as e {
            this.Flash("打开失败：" e.Message, 0xE0713F)
        }
    }

    OpenUrl(it) {
        if this.opened.Has(it.target) {
            rec := this.opened[it.target]
            if (rec.h && WinExist("ahk_id " rec.h)) {
                this.ForceActivate(rec.h)
                return
            }
        }
        host := this.HostOf(it.target)
        if (StrLen(host) > 3 && this.ActivateBrowserByHost(host))
            return
        try {
            Run it.target
            SetTimer(() => this.CaptureWindow(it.target), -1000)
        } catch as e {
            this.Flash("打开失败：" e.Message, 0xE0713F)
        }
    }

    ActivateBrowserByHost(host) {
        old := A_TitleMatchMode
        SetTitleMatchMode 2
        found := 0
        for cls in ["Chrome_WidgetWin_1", "MozillaWindowClass", "IEFrame"] {
            try {
                for h in WinGetList("ahk_class " cls) {
                    if (h = this.hwnd)
                        continue
                    if InStr(WinGetTitle("ahk_id " h), host) {
                        found := h
                        break 2
                    }
                }
            }
        }
        SetTitleMatchMode old
        if (found) {
            this.ForceActivate(found)
            return true
        }
        return false
    }

    CaptureWindow(key) {
        h := 0
        try {
            a := WinActive("A")
            if (a && a != this.hwnd)
                h := a
            if (!h) {
                for cls in ["Chrome_WidgetWin_1", "MozillaWindowClass"] {
                    hh := WinExist("ahk_class " cls)
                    if (hh) {
                        h := hh
                        break
                    }
                }
            }
        }
        if (h)
            this.opened[key] := {h: h}
    }

    ForceActivate(h) {
        try {
            if DllCall("user32\IsIconic", "ptr", h)
                WinRestore("ahk_id " h)
            WinActivate("ahk_id " h)
        }
    }

    ; ---------- 菜单 ----------
    CardMenu(idx) {
        ck := this.CurrentTab().key
        list := this.items.%ck%
        if (idx > list.Length)
            return
        it := list[idx]
        m := Menu()
        m.Add("打开", (*) => this.OpenItem(it, ck))
        m.Add("重命名…", (*) => this.Rename(idx))
        m.Add()
        m.Add("复制路径", (*) => this.CopyTarget(it))
        m.Add("删除", (*) => this.Remove(idx))
        m.Show()
    }

    CopyTarget(it) {
        A_Clipboard := it.target
        this.Flash("已复制：" it.target, 0x8A93A6)
    }

    Rename(idx) {
        ck := this.CurrentTab().key
        list := this.items.%ck%
        if (idx > list.Length)
            return
        it := list[idx]
        wasTop := this.topmost
        if (wasTop)
            try WinSetAlwaysOnTop(0, "ahk_id " this.hwnd)
        ib := InputBox("给这一项起个新名字：", "重命名", "w360 h150", it.name)
        if (wasTop)
            try WinSetAlwaysOnTop(1, "ahk_id " this.hwnd)
        if (ib.Result != "OK")
            return
        nm := Trim(ib.Value)
        if (nm = "")
            return
        it.name := nm
        this.SaveCfg()
        this.Flash("已重命名为：" nm, 0x6FB98C)
        this.Paint()
    }

    Remove(idx) {
        ck := this.CurrentTab().key
        list := this.items.%ck%
        if (idx > list.Length)
            return
        it := list[idx]
        r := MsgBox("确定删除「" it.name "」？`n`n" it.target, "删除确认", "YesNo Icon? Owner" this.hwnd)
        if (r != "Yes")
            return
        list.RemoveAt(idx)
        this.SaveCfg()
        this.Flash("已删除：" it.name, 0x8A93A6)
        this.Paint()
    }

    ; ---------- 提示 ----------
    Flash(txt, clr, ms := 3000) {
        this.msg := txt
        this.msgClr := clr
        if (this.msgTimer) {
            SetTimer(this.msgTimer, 0)
            this.msgTimer := 0
        }
        fn := (*) => (this.msg := "", this.msgTimer := 0, this.Paint())
        this.msgTimer := fn
        SetTimer(fn, -ms)
        this.Paint()
    }

    ; ---------- 配置 ----------
    LoadCfg() {
        if !FileExist(DropBoard.CFG)
            return
        try {
            txt := FileRead(DropBoard.CFG, "UTF-8")
            data := JParse(txt)
            if !(data is Map)
                return
            if data.Has("tab") {
                tk := data["tab"]
                for i, t in DropBoard.TABS {
                    if (t.key = tk)
                        this.tabIdx := i
                }
            }
            if data.Has("collapsed")
                this.collapsed := (data["collapsed"] = true)
            if data.Has("topmost")
                this.topmost := (data["topmost"] = true)
            if data.Has("window") && (data["window"] is Map) {
                w := data["window"]
                if w.Has("x")
                    this.pos.x := w["x"]
                if w.Has("y")
                    this.pos.y := w["y"]
            }
            if data.Has("items") && (data["items"] is Map) {
                im := data["items"]
                for tk in ["folder", "file", "url"] {
                    if !im.Has(tk)
                        continue
                    arr := im[tk]
                    if !(arr is Array)
                        continue
                    lst := this.items.%tk%
                    for e in arr {
                        if !(e is Map)
                            continue
                        nm := e.Has("name") ? e["name"] : ""
                        tg := e.Has("target") ? e["target"] : ""
                        sb := e.Has("sub") ? e["sub"] : ""
                        if (tg = "")
                            continue
                        if (nm = "")
                            nm := this.NameOf(tk, tg)
                        if (sb = "")
                            sb := this.SubOf(tk, tg)
                        lst.Push({name: nm, sub: sb, target: tg, added: e.Has("added") ? e["added"] : ""})
                    }
                }
            }
        }
    }

    SaveCfg() {
        if !IsObject(this.gui)
            return
        try {
            WinGetPos(&wx, &wy, , , "ahk_id " this.hwnd)
            if (wx != "" && wy != "")
                this.pos := {x: wx, y: wy}
        }
        q := Chr(34)
        out := "{" "`n"
        out .= "  " q "version" q ": 1," "`n"
        out .= "  " q "tab" q ": " q JE(this.CurrentTab().key) q "," "`n"
        out .= "  " q "collapsed" q ": " (this.collapsed ? "true" : "false") "," "`n"
        out .= "  " q "topmost" q ": " (this.topmost ? "true" : "false") "," "`n"
        out .= "  " q "window" q ": { " q "x" q ": " (this.pos.x = "" ? 0 : this.pos.x) ", " q "y" q ": " (this.pos.y = "" ? 0 : this.pos.y) " }," "`n"
        out .= "  " q "items" q ": {" "`n"
        first := true
        for i, t in DropBoard.TABS {
            lst := this.items.%t.key%
            out .= (first ? "" : "," "`n") "    " q t.key q ": ["
            first := false
            if (lst.Length = 0) {
                out .= "]"
                continue
            }
            out .= "`n"
            for j, it in lst {
                out .= "      { " q "name" q ": " q JE(it.name) q ", " q "target" q ": " q JE(it.target) q ", " q "sub" q ": " q JE(it.sub) q ", " q "added" q ": " q JE(it.added) q " }"
                out .= (j < lst.Length ? "," "`n" : "`n")
            }
            out .= "    ]"
        }
        out .= "`n  }" "`n" "}" "`n"
        f := FileOpen(DropBoard.CFG, "w", "UTF-8")
        if !f
            return
        f.Write(out)
        f.Close()
    }

    Quit() {
        this.SaveCfg()
        ExitApp()
    }
}

UrlDecode(s) {
    out := ""
    i := 1
    n := StrLen(s)
    while (i <= n) {
        ch := SubStr(s, i, 1)
        if (ch = "%") {
            buf := Buffer(256, 0)
            pos := 0
            while (i + 2 <= n) {
                hx := SubStr(s, i + 1, 2)
                if !RegExMatch(hx, "^[0-9A-Fa-f]{2}$")
                    break
                NumPut("uchar", Integer("0x" hx), buf, pos)
                pos += 1
                i += 3
                if (pos >= 200)
                    break
            }
            if (pos > 0) {
                out .= StrGet(buf, pos, "UTF-8")
                continue
            }
        }
        out .= ch
        i += 1
    }
    return out
}

; ---------------- 小工具 ----------------
JoinArr(a, sep) {
    out := ""
    for i, v in a
        out .= (i = 1 ? "" : sep) v
    return out
}

JE(s) {
    s := StrReplace(s, "\", "\\")
    s := StrReplace(s, Chr(34), "\" Chr(34))
    s := StrReplace(s, "`n", "\n")
    s := StrReplace(s, "`r", "\r")
    s := StrReplace(s, "`t", "\t")
    return s
}

; ---------------- JSON 解析（最小实现） ----------------
JParse(txt) {
    p := {s: txt, i: 1, n: StrLen(txt)}
    JSep(p)
    return JVal(p)
}

JSep(p) {
    while (p.i <= p.n) {
        c := SubStr(p.s, p.i, 1)
        if (c = " " || c = "`t" || c = "`r" || c = "`n")
            p.i += 1
        else
            break
    }
}

JVal(p) {
    JSep(p)
    c := SubStr(p.s, p.i, 1)
    if (c = "{")
        return JObj(p)
    if (c = "[")
        return JArr(p)
    if (c = Chr(34))
        return JStr(p)
    if (c = "t") {
        p.i += 4
        return true
    }
    if (c = "f") {
        p.i += 5
        return false
    }
    if (c = "n") {
        p.i += 4
        return ""
    }
    return JNum(p)
}

JObj(p) {
    m := Map()
    p.i += 1
    JSep(p)
    if (SubStr(p.s, p.i, 1) = "}") {
        p.i += 1
        return m
    }
    loop {
        JSep(p)
        if (SubStr(p.s, p.i, 1) != Chr(34))
            break
        k := JStr(p)
        JSep(p)
        if (SubStr(p.s, p.i, 1) = ":")
            p.i += 1
        v := JVal(p)
        m[k] := v
        JSep(p)
        c := SubStr(p.s, p.i, 1)
        p.i += 1
        if (c != ",")
            break
    }
    return m
}

JArr(p) {
    a := []
    p.i += 1
    JSep(p)
    if (SubStr(p.s, p.i, 1) = "]") {
        p.i += 1
        return a
    }
    loop {
        v := JVal(p)
        a.Push(v)
        JSep(p)
        c := SubStr(p.s, p.i, 1)
        p.i += 1
        if (c != ",")
            break
    }
    return a
}

JStr(p) {
    out := ""
    p.i += 1
    while (p.i <= p.n) {
        c := SubStr(p.s, p.i, 1)
        if (c = Chr(34)) {
            p.i += 1
            break
        }
        if (c = "\") {
            p.i += 1
            e := SubStr(p.s, p.i, 1)
            if (e = Chr(34))
                out .= Chr(34)
            else if (e = "\")
                out .= "\"
            else if (e = "/")
                out .= "/"
            else if (e = "b")
                out .= Chr(8)
            else if (e = "f")
                out .= Chr(12)
            else if (e = "n")
                out .= "`n"
            else if (e = "r")
                out .= "`r"
            else if (e = "t")
                out .= "`t"
            else if (e = "u") {
                hex := SubStr(p.s, p.i + 1, 4)
                out .= Chr(Integer("0x" hex))
                p.i += 4
            } else
                out .= e
            p.i += 1
            continue
        }
        out .= c
        p.i += 1
    }
    return out
}

JNum(p) {
    st := p.i
    while (p.i <= p.n) {
        c := SubStr(p.s, p.i, 1)
        if InStr("0123456789+-.eE", c)
            p.i += 1
        else
            break
    }
    v := SubStr(p.s, st, p.i - st)
    return (v = "" ? "" : Number(v))
}

; ---------------- 启动 ----------------
Persistent()
app := DropBoard()
