﻿Init_betrayal()
{
	local
	global vars, settings, Json
	
	check := {"t": "transportation", "f": "fortification", "r": "research", "i": "intervention"}
	settings.features.betrayal := LLK_IniRead("ini\config.ini", "Features", "enable betrayal-info", 0)
	If FileExist("data\Betrayal.ini")
		FileDelete, data\Betrayal.ini
	
	settings.betrayal := {}
	settings.betrayal.fSize := LLK_IniRead("ini\betrayal info.ini", "Settings", "font-size", settings.general.fSize)
	LLK_FontDimensions(settings.betrayal.fSize, font_height, font_width)
	settings.betrayal.fHeight := font_height, settings.betrayal.fWidth := font_width
	settings.betrayal.trans := LLK_IniRead("ini\betrayal info.ini", "Settings", "transparency", 220)
	settings.betrayal.dColors := ["00D000", "Yellow", "E90000"]
	settings.betrayal.colors := []
	settings.betrayal.colors[0] := "White"
	settings.betrayal.sPrio := vars.client.h * (2/15)
	settings.betrayal.ruthless := LLK_IniRead("ini\betrayal info.ini", "settings", "ruthless", 0)
	
	Loop 3
		settings.betrayal.colors[A_Index] := LLK_IniRead("ini\betrayal info.ini", "settings", "rank "A_Index " color", settings.betrayal.dColors[A_Index])
	
	ini := LLK_IniRead("ini\betrayal info.ini", "settings", "board")
	If !IsObject(vars.betrayal.board) && ini
		vars.betrayal.board := Json.Load(ini)

	vars.betrayal.members := Json.Load(LLK_FileRead("data\Betrayal.json"))
	vars.betrayal.divisions := {"transportation": {}, "fortification": {}, "research": {}, "intervention": {}} ;each object stores the BIS members of a given division
	vars.betrayal.divisions.list := ["transportation", "fortification", "research", "intervention"]
	
	If !FileExist("ini\betrayal info.ini")
	{
		IniWrite, % settings.general.fSize, ini\betrayal info.ini, Settings, font-size
		IniWrite, 220, ini\betrayal info.ini, Settings, transparency
		For member in vars.betrayal.members
			IniWrite, transportation=0`nfortification=0`nresearch=0`nintervention=0, ini\betrayal info.ini, % member
	}
	If !InStr(LLK_FileRead("ini\betrayal info.ini"), " - ruthless")
		For member in vars.betrayal.members
			IniWrite, transportation=0`nfortification=0`nresearch=0`nintervention=0, ini\betrayal info.ini, % member " - ruthless"
	
	For member in vars.betrayal.members
	{
		vars.betrayal.members[member].ranks := {}
		For division in vars.betrayal.divisions
			vars.betrayal.members[member].ranks[division] := LLK_IniRead("ini\betrayal info.ini", member (settings.betrayal.ruthless ? " - ruthless" : ""), division, 0)
	}
	BetrayalRefreshRanks()
}

Betrayal()
{
	local
	global vars, settings
	
	ThisHotkey_copy := A_ThisHotkey, start := A_TickCount
	If !IsObject(vars.betrayal.board)
		vars.betrayal.board := {}

	Loop, Parse, % "*~!+#^"
		ThisHotkey_copy := StrReplace(ThisHotkey_copy, A_LoopField)
	
	If GetKeyState("RButton", "P")
	{
		BetrayalCalibrate()
		Return
	}
	Else BetrayalSearch(ThisHotkey_copy)
}

BetrayalCalibrate(cHWND := "")
{
	local
	global vars, settings
	static pBetrayal, wBetrayal, hBetrayal, hbmBetrayal, hdcBetrayal, obmBetrayal, gBetrayal

	If cHWND && (cHWND = vars.hwnd.betrayal_setup.ddl) ;function is called by interacting with the screen-cap window
	{
		If InStr(A_GuiControl, "-----")
			Return
		Gdip_SaveBitmapToFile(pBetrayal, "img\Recognition (" vars.client.h "p)\Betrayal\" A_GuiControl ".bmp", 100)
	}
	Else
	{
		Clipboard := ""
		SendInput, +#{s}
		WinWaitActive, ahk_group snipping_tools,, 2
		WinWaitNotActive, ahk_group snipping_tools
		pBetrayal := Gdip_CreateBitmapFromClipboard()
		If (pBetrayal < 0)
		{
			LLK_ToolTip("screen-cap failed",,,,, "red")
			Return
		}
		Else
		{
			Gdip_GetImageDimensions(pBetrayal, wBetrayal, hBetrayal)
			hbmBetrayal := CreateDIBSection(wBetrayal, hBetrayal)
			hdcBetrayal := CreateCompatibleDC()
			obmBetrayal := SelectObject(hdcBetrayal, hbmBetrayal)
			gBetrayal := Gdip_GraphicsFromHDC(hdcBetrayal)
			Gdip_SetInterpolationMode(gBetrayal, 0)
			Gdip_DrawImage(gBetrayal, pBetrayal, 0, 0, wBetrayal, hBetrayal, 0, 0, wBetrayal, hBetrayal, 1)
		}
		Gui, betrayal_setup: New, -DPIScale -Caption +LastFound +AlwaysOnTop +ToolWindow +Border HWNDhwnd
		Gui, betrayal_setup: Margin, 12, 4
		Gui, betrayal_setup: Color, Black
		Gui, betrayal_setup: Font, % "s"settings.general.fSize " cWhite", Fontin SmallCaps
		vars.hwnd.betrayal_setup := {"main": hwnd}

		Gui, betrayal_setup: Add, Picture, % "Section BackgroundTrans", HBitmap:*%hbmBetrayal%
		ddl := "transportation||fortification|research|intervention|----------|"
		For member in vars.betrayal.members
			ddl .= member "|"
		Gui, betrayal_setup: Add, DDL, ys Section cBlack HWNDhwnd gBetrayalCalibrate, % ddl
		vars.hwnd.betrayal_setup.ddl := hwnd
		Gui, betrayal_setup: Add, Text, xs Section wp, % "press esc, or click into the client to abort"
		Gui, betrayal_setup: Show, NA x10000 y10000
		WinGetPos,,, w, h, % "ahk_id " vars.hwnd.betrayal_setup.main
		Gui, betrayal_setup: Show, % "x"vars.client.xc - w//2 " y"vars.client.yc - h//2
		Loop ;use this kind of loop instead of a hard-coded hotkey to close this setup-window
		{
			If !WinActive("ahk_id "vars.hwnd.betrayal_setup.main) || GetKeyState("ESC", "P")
			{
				If IsObject(vars.hwnd.betrayal_setup)
					LLK_ToolTip("screen-cap aborted",,,,, "red")
				Else LLK_ToolTip("success",,,,, "lime")
				break
			}
		}
	}
	SelectObject(hdcBetrayal, obmBetrayal)
	DeleteObject(hbmBetrayal)
	DeleteDC(hdcBetrayal)
	Gdip_DeleteGraphics(gBetrayal)
	Gdip_DisposeImage(pBetrayal)
	vars.hwnd.Delete("betrayal_setup")
	Gui, betrayal_setup: Destroy
}

BetrayalInfo(member, div := "", x := "", y := "")
{
	local
	global vars, settings

	div_check := {"t": "transportation", "f": "fortification", "r": "research", "i": "intervention"}
	Gui, New, -DPIScale -Caption +LastFound +AlwaysOnTop +ToolWindow +E0x02000000 +E0x00080000 HWNDbetrayal_info
	Gui, %betrayal_info%: Margin, 0, 0
	Gui, %betrayal_info%: Color, Black
	Gui, %betrayal_info%: Font, % "s"settings.betrayal.fSize " cWhite", Fontin SmallCaps
	hwnd_old := vars.hwnd.betrayal_info.main, vars.hwnd.betrayal_info := {"main": betrayal_info}, vars.hwnd.betrayal_info.active := member

	parse := []
	For key, division in vars.betrayal.divisions.list
		parse.Push(vars.betrayal.members[member].rewards[division][settings.betrayal.ruthless ? 2 : 1]) ;push the active member's reward-texts into an array
	LLK_PanelDimensions(parse, settings.betrayal.fSize, width, height, "center") ;use the array to get the maximum width/height among all text-boxes

	Loop, Parse, % member ", 1, transportation, t, fortification, f, research, r, intervention, i", `,, % A_Space ;create the GUI: header with name, left-side column with TFRI, right-side column with rewards
	{
		division := (StrLen(A_LoopField) = 1) ? div_check[A_LoopField] : A_LoopField
		text := vars.betrayal.members[member].rewards[division][settings.betrayal.ruthless ? 2 : 1]
		color := settings.betrayal.colors[vars.betrayal.members[member].ranks[division]]
		
		If (A_LoopField = member)
			pos := " x"settings.betrayal.fWidth*2 " y0 Section w"width
		Else If (A_LoopField = "transportation")
			pos := " xs Section"
		Else If (StrLen(A_LoopField) = 1)
			pos := " xp-"settings.betrayal.fWidth*2 " yp"
		Else pos := " xs"
		
		If (A_LoopField = member)
		{
			Gui, %betrayal_info%: Add, Text, % "Center BackgroundTrans Border HWNDhwnd" pos, % member
			vars.hwnd.betrayal_info[member] := hwnd
			Gui, %betrayal_info%: Add, Progress, % "BackgroundBlack Disabled cRed Border xp yp wp hp HWNDhwnd range0-500", 0
			vars.hwnd.betrayal_info[member "_progress"] := hwnd
		}
		Else If (StrLen(A_Loopfield) = 1)
		{
			color1 := (A_LoopField = SubStr(div, 1, 1)) ? "606060" : "Black"
			Gui, %betrayal_info%: Add, Text, % pos " center BackgroundTrans Border 0x200 hp w"settings.betrayal.fWidth* 2, % (A_LoopField = 1) ? " " : A_LoopField
			Gui, %betrayal_info%: Add, Progress, % "xp yp wp hp Background"color1, 0
		}
		Else
		{
			Gui, %betrayal_info%: Add, Text, % "center BackgroundTrans HWNDhwnd Border c"color pos " w"width, % text
			vars.hwnd.betrayal_info[A_Loopfield "_"] := hwnd
		}
	}
	Gui, %betrayal_info%: Show, % "NA x10000 y10000"
	WinGetPos,,, w, h, % "ahk_id "vars.hwnd.betrayal_info.main
	vars.betrayal.wInfo := w
	
	If x && y ;coordinates passed through function-parameters (when mouse is hovering over the prio-view on the top-edge of the screen)
		xPos := x - w/2, yPos := y
	Else
	{
		If (vars.general.xMouse + w/2 > vars.client.x + vars.client.w)
			xPos := vars.client.x + vars.client.w - w
		Else xPos := (vars.general.xMouse - w/2 < vars.client.x) ? vars.client.x : vars.general.xMouse - w/2
		If (A_Gui = DummyGUI(vars.hwnd.settings.main))
			yPos := (vars.general.yMouse + settings.general.fHeight + h > vars.client.y + vars.client.h) ? vars.client.y + vars.client.h - h : vars.general.yMouse + settings.general.fHeight
		Else yPos := (vars.general.yMouse + 2*settings.betrayal.fHeight + h > vars.client.y + vars.client.h) ? vars.client.y + vars.client.h - h : vars.general.yMouse + 2*settings.betrayal.fHeight
	}
	Gui, %betrayal_info%: Show, % "NA x"xPos " y"yPos
	LLK_Overlay(hwnd_old, "destroy")
	;If WinExist("ahk_id "hwnd_old)
	;	Gui, %hwnd_old%: Destroy
}

BetrayalPrioview()
{
	local
	global vars, settings
	
	unspec := 0, added := 0
	div_check := {"trans": "transportation", "fort": "fortification", "research": "research", "inter": "intervention"}
	Gui, New, -DPIScale -Caption +LastFound +AlwaysOnTop +ToolWindow +E0x02000000 +E0x00080000 HWNDbetrayal_prioview ;the 'E0x' styles improve UI rendering and reduce flicker but require inverted control stacking
	Gui, %betrayal_prioview%: Margin, % settings.betrayal.fWidth, 0
	Gui, %betrayal_prioview%: Color, 202020
	Gui, %betrayal_prioview%: Font, % "s"settings.betrayal.fSize " cWhite", Fontin SmallCaps
	WinSet, TransColor, 202020
	hwnd_old := WinExist("ahk_id "vars.hwnd.betrayal_prioview.main) ? vars.hwnd.betrayal_prioview.main : "", vars.hwnd.betrayal_prioview := {"main": betrayal_prioview}
	LLK_PanelDimensions(["gravicius"], settings.betrayal.fSize, width, height)

	For member in vars.betrayal.members
		If !vars.betrayal.board[member]
			unspec += 1

	Loop, Parse, % "trans, fort, unassigned, research, inter", `,, % A_Space
	{
		division := (A_LoopField = "unassigned") ? "" : div_check[A_LoopField]
		If (A_LoopField = "unassigned")
		{
			Gui, %betrayal_prioview%: Add, Text, % (A_Index = 1 ? "" : "ys ") " w"2*width " Section Center HWNDhwnd BackgroundTrans Border cGray", % A_LoopField
			Gui, %betrayal_prioview%: Add, Progress, % "xp yp wp hp cRed Disabled BackgroundBlack range0-500 HWNDhwnd", 0 ;progress and text controls are stacked in reverse order for the 'E0x' styles
			vars.hwnd.betrayal_prioview.unassigned_progress := hwnd
		}
		Else
		{
			color := vars.betrayal.divisions[div_check[A_LoopField]].Count() ? settings.betrayal.colors.1 : "Gray"
			For member in vars.betrayal.divisions[div_check[A_LoopField]] ;check if division has the BIS constellation
			{
				;if a given member is not in this division, check if they are in a secondary T1 position
				If (vars.betrayal.board[member] != div_check[A_LoopField]) && !LLK_HasVal(vars.betrayal.members[member].first, vars.betrayal.board[member]) ;cont
				|| (vars.betrayal.divisions[div_check[A_LoopField]].Count() = 1) && (vars.betrayal.board[member] != division) ;don't highlight a division if it only has one T1 spot and that member is in a different T1 spot
					color := "Gray"
			}

			pos := (A_LoopField = "research") ? "ys y0 " : (A_Index = 1) ? "" : "ys "
			Gui, %betrayal_prioview%: Add, Text, % pos " Section w"width " Center BackgroundTrans Border c"color, % A_LoopField
			Gui, %betrayal_prioview%: Add, Progress, % "xp yp wp hp cRed Border BackgroundBlack range0-500 HWNDhwnd", 0
			vars.hwnd.betrayal_prioview[A_LoopField "_progress"] := hwnd
		}

		For member in vars.betrayal.members
		{
			If (division = vars.betrayal.board[member])
			{
				If IsObject(vars.betrayal.members[member].first) && !LLK_HasVal(vars.betrayal.members[member].first, division) ;cont
				|| !IsObject(vars.betrayal.members[member].first) && IsObject(vars.betrayal.members[member].second) && !LLK_HasVal(vars.betrayal.members[member].second, division)
					color := settings.betrayal.colors.3
				Else If !IsObject(vars.betrayal.members[member].first) && IsObject(vars.betrayal.members[member].second) && LLK_HasVal(vars.betrayal.members[member].second, division)
					color := settings.betrayal.colors.1
				Else If LLK_HasVal(vars.betrayal.members[member].first, division)
					color := settings.betrayal.colors.1
				Else color := "White"

				pos := (!division && added = 0) ? "Section xs " : (added = unspec//2) ? "Section x+0 ys " : "xs "
				Gui, %betrayal_prioview%: Add, Text, % pos " w"width " BackgroundTrans Border c"color, % " " member
				Gui, %betrayal_prioview%: Add, Progress, % "xp yp wp hp Background" (vars.hwnd.betrayal_info.active = member ? "606060" : "Black") " cRed Border range0-500 HWNDhwnd", 0
				vars.hwnd.betrayal_prioview[member "_progress"] := hwnd
				If !division
					added += 1
			}
		}
	}
	Gui, %betrayal_prioview%: Show, % "NA x10000 y10000"
	WinGetPos,,, w, h, % "ahk_id "vars.hwnd.betrayal_prioview.main
	Gui, %betrayal_prioview%: Show, % "NA x"vars.client.xc - w//2 " y"vars.client.y
	vars.betrayal.hPrioview := h
	LLK_Overlay(hwnd_old, "destroy")
}

BetrayalRank(rank)
{
	local
	global vars, settings

	rank := (rank = "Space") ? 0 : rank, color := settings.betrayal.colors[rank]
	If vars.betrayal.divisions.HasKey(StrReplace(LLK_HasVal(vars.hwnd.betrayal_info, vars.general.cMouse), "_"))
	{
		division := StrReplace(LLK_HasVal(vars.hwnd.betrayal_info, vars.general.cMouse), "_")
		If (rank = vars.betrayal.divisions[division][vars.hwnd.betrayal_info.active].2)
			Return
		GuiControl, +c%color%, % vars.hwnd.betrayal_info[division "_"] ;control's HWND tagged with "_" to avoid confusion with prio-view header's which are also stored under %division%
		GuiControl, movedraw, % vars.hwnd.betrayal_info[division "_"]

		vars.betrayal.members[vars.hwnd.betrayal_info.active].ranks[division] := rank
		IniWrite, % rank, ini\betrayal info.ini, % vars.hwnd.betrayal_info.active (settings.betrayal.ruthless ? " - ruthless" : ""), % division
		BetrayalRefreshRanks()
		If !WinActive("ahk_id " vars.hwnd.settings.main)
			BetrayalPrioview()
	}
	KeyWait, % A_ThisHotkey
}

BetrayalRefreshRanks()
{
	local
	global vars, settings

	For key, division in vars.betrayal.divisions.list
	{
		vars.betrayal.divisions[division] := {}
		For member in vars.betrayal.members
		{
			vars.betrayal.members[member].first := LLK_HasVal(vars.betrayal.members[member].ranks, 1,,, 1)
			vars.betrayal.members[member].second := LLK_HasVal(vars.betrayal.members[member].ranks, 2,,, 1)
			If (vars.betrayal.members[member].ranks[division] = 1)
				vars.betrayal.divisions[division][member] := 1 ;store member as a BIS position in this division
		}
	}
}

BetrayalSearch(hotkey)
{
	local
	global vars, settings
	
	prioview := 1, removed := [], delay := ["", 0]
	Loop, Files, % "img\Recognition ("vars.client.h "p)\Betrayal\*.bmp" ;delete any non-Betrayal or unintentionally saved files to prevent unnecessary scanning
	{
		parse := SubStr(A_LoopFileName, 1, InStr(A_LoopFileName, ".") - 1)
		If (parse = "") || !vars.betrayal.members.HasKey(parse) && !vars.betrayal.divisions.HasKey(parse)
			FileDelete, % "img\Recognition (" vars.client.h "p)\Betrayal\"parse ".bmp"
	}

	BetrayalPrioview()
	
	While GetKeyState(hotkey, "P")
	{
		If vars.general.cMouse && LLK_HasVal(vars.hwnd.betrayal_prioview, vars.general.cMouse)
			hover := [LLK_HasVal(vars.hwnd.betrayal_prioview, vars.general.cMouse), "betrayal_prioview"]
		Else If vars.general.cMouse && LLK_HasVal(vars.hwnd.betrayal_info, vars.general.cMouse)
			hover := [LLK_HasVal(vars.hwnd.betrayal_info, vars.general.cMouse), "betrayal_info"]
		Else hover := ""
		
		If (SubStr(hover.1, 0, 1) = "_") ;exclusion-rule to avoid interaction with division text-panels (the ones which display the rewards)
			hover := ""

		KeyWait, RButton, D T0.1
		If !ErrorLevel && hover
		{
			;object := StrReplace(hover.2, "_") ;HWND-objects can be derived from the GUI-name by removing the underscore (GUI: this_name, Object: vars.hwnd.thisname)
			If LLK_Progress(vars.hwnd[hover.2][hover.1], "RButton", vars.hwnd[hover.2][hover.1])
			{
				If (StrReplace(hover.1, "_progress") = "unassigned") ;reset the whole board
					vars.betrayal.board := {}
				Else If vars.betrayal.members.HasKey(StrReplace(hover.1, "_progress")) ;set a single member to unassigned
				{
					vars.betrayal.board[StrReplace(hover.1, "_progress")] := ""
					removed.Push(StrReplace(hover.1, "_progress"))
				}
				Else
				{
					For member in vars.betrayal.members
					{
						If InStr(vars.betrayal.board[member], StrReplace(hover.1, "_progress")) ;set all members within a specific division to unassigned
							vars.betrayal.board[member] := ""
					}
				}
				vars.hwnd.betrayal_info.active := ""
				BetrayalPrioview()
				LLK_Overlay(vars.hwnd.betrayal_info.main, "destroy")
				KeyWait, RButton
			}
		}
		If (vars.general.wMouse = vars.hwnd.betrayal_prioview.main) && vars.betrayal.members.HasKey(StrReplace(hover.1, "_progress")) ;&& (!WinExist("ahk_id " vars.hwnd.betrayal_info.main) || (StrReplace(hover.1, "_progress") != vars.hwnd.betrayal_info.active))
		{
			If (StrReplace(hover.1, "_progress") = delay.1)
				delay.2 += 1
			Else delay := [StrReplace(hover.1, "_progress"), 1]
			If (delay.2 = 2) && (delay.1 != vars.hwnd.betrayal_info.active)
			{
				BetrayalInfo(StrReplace(hover.1, "_progress"), vars.betrayal.board[StrReplace(hover.1, "_progress")], vars.general.xMouse, vars.client.y + 1.05*vars.betrayal.hPrioview)
				BetrayalPrioview()
				delay := ["", 0]
			}
			continue
		}
		Else delay := ["", 0]

		If xPrev && LLK_InRange(xPrev, vars.general.xMouse, settings.betrayal.sPrio/8) && LLK_InRange(yPrev, vars.general.yMouse, settings.betrayal.sPrio/8) ;only scan the screen if mouse has moved a bit
		|| (vars.general.wMouse = vars.hwnd.betrayal_info.main) || !GetKeyState(hotkey, "P")
			continue
		
		member1 := "", division1 := "", LIST0 := ""
		xPrev := vars.general.xMouse, yPrev := vars.general.yMouse ;mouse-position at the start of this loop
		pHaystack := Gdip_BitmapFromHWND(vars.hwnd.poe_client, 1)
		
		Loop, Files, % "img\Recognition ("vars.client.h "p)\Betrayal\*.bmp"
		{
			parse := SubStr(A_LoopFileName, 1, InStr(A_LoopFileName, ".") - 1)
			If vars.betrayal.divisions.HasKey(parse) ;|| LLK_HasVal(removed, parse) ;skip divisions and recently unassigned members
				continue
			pNeedle := Gdip_CreateBitmapFromFile(A_LoopFilePath)
			width := Gdip_GetImageWidth(pNeedle)
			x1 := (vars.general.xMouse - vars.client.x - vars.client.w/3 < 0) ? 0 : vars.general.xMouse - vars.client.x - vars.client.w/3
			x2 := (vars.general.xMouse - vars.client.x + vars.client.w/3 > vars.client.w) ? vars.client.w - 1 : vars.general.xMouse - vars.client.x + vars.client.w/3
			y1 := (vars.general.yMouse - vars.client.y - vars.client.h/4 < 0) ? 0 : vars.general.yMouse - vars.client.y - vars.client.h/4
			y2 := (vars.general.yMouse - vars.client.y + vars.client.h/4 > vars.client.h) ? vars.client.h - 1 : vars.general.yMouse - vars.client.y + vars.client.h/4 > vars.client.h
			result := Gdip_ImageSearch(pHaystack, pNeedle, LIST, x1, y1, x2, y2, vars.imagesearch.variation + 20,, 1, 1)
			Gdip_DisposeImage(pNeedle)

			If !LLK_InRange(xPrev, vars.general.xMouse, settings.betrayal.sPrio/8) || !LLK_InRange(yPrev, vars.general.yMouse, settings.betrayal.sPrio/8) ;if cursor was moved since the start, restart the loop
				break

			If (result > 0)
			{
				member1 := StrReplace(A_LoopFileName, ".bmp")
				LIST0 := LIST "," width
				Break
			}
		}


		;if cursor was moved since the start or if there was no result, restart the loop
		If !member1 || !LLK_InRange(xPrev, vars.general.xMouse, settings.betrayal.sPrio/8) || !LLK_InRange(yPrev, vars.general.yMouse, settings.betrayal.sPrio/8) || !GetKeyState(hotkey, "P")
		{
			Gdip_DisposeImage(pHaystack)
			continue
		}	

		For key, division in vars.betrayal.divisions.list ;scan the division
		{
			If !FileExist("img\Recognition ("vars.client.h "p)\Betrayal\"division ".bmp")
				continue
	
			pNeedle := Gdip_CreateBitmapFromFile("img\Recognition ("vars.client.h "p)\Betrayal\"division ".bmp")
			width := Gdip_GetImageWidth(pNeedle)
			result := Gdip_ImageSearch(pHaystack, pNeedle, LIST, x1, y1, x2, y2, vars.imagesearch.variation + 20,, 1, 1)
			Gdip_DisposeImage(pNeedle)

			If !LLK_InRange(xPrev, vars.general.xMouse, settings.betrayal.sPrio/8) || !LLK_InRange(yPrev, vars.general.yMouse, settings.betrayal.sPrio/8) ;if cursor was moved since the start, restart the loop
				break

			If (result > 0)
			{
				division1 := division
				LIST0 := LIST "," width
				Break
			}
		}
		Gdip_DisposeImage(pHaystack)

		;make sure the cursor hasn't moved too much during the scan (to prevent extreme niche cases where members and divisions get mixed up)
		If LLK_InRange(xPrev, vars.general.xMouse, settings.betrayal.sPrio/8) && LLK_InRange(yPrev, vars.general.yMouse, settings.betrayal.sPrio/8)
		{
			If member1
				vars.betrayal.board[member1] := division1
			
			If member1 && (member1 != vars.hwnd.betrayal_info.active)
				BetrayalInfo(member1, division1)
			BetrayalPrioview()
		}
	}
	Gui, % vars.hwnd.betrayal_prioview.main ": Destroy"
	LLK_Overlay(vars.hwnd.betrayal_info.main, "destroy")
	vars.hwnd.Delete("betrayal_info"), vars.hwnd.Delete("betrayal_prioview")
}
