-- 移动到… Quick Action(v2:纯 shell 搬运,不碰访达,不提权)
-- 选中项移动到用户选择的文件夹;目标存在同名项时弹框三选:替换 / 两者都保留 / 跳过。
-- 搬运/删除全部走 do shell script 的 mv/test/basename,不发送任何 Apple Events 给访达。

on run {input, parameters}
	if input is {} then return input
	try
		set destFolder to (choose folder with prompt "移动到哪个文件夹?")
	on error number -128
		return input
	end try
	set dd to my destDir(destFolder)
	set trashDir to (do shell script "echo $HOME/.Trash/")
	set failed to {}
	repeat with anItem in input
		set srcPosix to my toPosix(anItem)
		set choice to "move"
		if my hasConflict(srcPosix, dd) then
			set nm to my baseName(srcPosix)
			try
				set btn to button returned of (display dialog "目标文件夹已存在同名项:" & return & nm & return & return & "请选择处理方式:" buttons {"跳过", "两者都保留", "替换"} default button "两者都保留" with icon caution)
			on error number -128
				set btn to "跳过"
			end try
			if btn is "替换" then
				set choice to "replace"
			else if btn is "两者都保留" then
				set choice to "keepboth"
			else
				set choice to "skip"
			end if
		end if
		set em to my moveOne(srcPosix, dd, choice, trashDir)
		if em is not "" then set end of failed to em
	end repeat
	if (count of failed) > 0 then
		set AppleScript's text item delimiters to return
		set report to (failed as text)
		set AppleScript's text item delimiters to ""
		display dialog "有 " & (count of failed) & " 项移动失败:" & return & report buttons {"好"} default button "好" with icon caution
	end if
	return input
end run

-- 把输入项(Finder 传入的 alias,或 POSIX 路径文本)统一成 POSIX 路径文本
on toPosix(anItem)
	if class of anItem is text then
		return POSIX path of ((POSIX file anItem) as alias)
	else
		return POSIX path of (anItem as alias)
	end if
end toPosix

-- 目标文件夹 POSIX 路径(确保以 / 结尾)
on destDir(destFolder)
	set p to POSIX path of destFolder
	if p does not end with "/" then set p to p & "/"
	return p
end destDir

-- 项目名(文件或文件夹)
on baseName(srcPosix)
	return do shell script "/usr/bin/basename " & quoted form of srcPosix
end baseName

-- 目标里是否已存在同名项
on hasConflict(srcPosix, dd)
	set target to dd & my baseName(srcPosix)
	try
		do shell script "/bin/test -e " & quoted form of target
		return true
	on error
		return false
	end try
end hasConflict

-- 执行单项移动。choice: "move" | "replace" | "keepboth" | "skip"
-- 成功或跳过返回 "";失败返回错误信息文本。绝不弹密码:失败即返回错误由上层汇总提示。
on moveOne(srcPosix, dd, choice, trashDir)
	if choice is "skip" then return ""
	try
		set nm to my baseName(srcPosix)
		if choice is "replace" then
			-- 旧的先移入废纸篓(可恢复),再把新的移入;若废纸篓里已有同名项才改名避免冲突
			set trashName to nm
			try
				do shell script "/bin/test -e " & quoted form of (trashDir & nm)
				set trashName to my uniqueName(trashDir, nm)
			end try
			set trashTarget to trashDir & trashName
			do shell script "/bin/mv " & quoted form of (dd & nm) & " " & quoted form of trashTarget
			do shell script "/bin/mv " & quoted form of srcPosix & " " & quoted form of (dd & nm)
		else if choice is "keepboth" then
			set newName to my uniqueName(dd, nm)
			do shell script "/bin/mv -n " & quoted form of srcPosix & " " & quoted form of (dd & newName)
		else
			do shell script "/bin/mv " & quoted form of srcPosix & " " & quoted form of (dd & nm)
		end if
		return ""
	on error errMsg
		return errMsg
	end try
end moveOne

-- 在目录 dir 下为 name 生成不冲突的新名字,如 "foo 2.txt"、"foo 3.txt"
on uniqueName(dir, name)
	set {base, ext} to my splitExt(name)
	set i to 2
	repeat
		if ext is "" then
			set candidate to base & " " & (i as text)
		else
			set candidate to base & " " & (i as text) & "." & ext
		end if
		try
			do shell script "/bin/test -e " & quoted form of (dir & candidate)
			set i to i + 1
		on error
			return candidate
		end try
	end repeat
end uniqueName

-- 把名字拆成 {主名, 扩展名};无扩展名则扩展名为 ""
on splitExt(fname)
	if fname contains "." then
		set AppleScript's text item delimiters to "."
		set parts to text items of fname
		set ext to last item of parts
		set base to (items 1 thru -2 of parts) as text
		set AppleScript's text item delimiters to ""
		return {base, ext}
	else
		return {fname, ""}
	end if
end splitExt
