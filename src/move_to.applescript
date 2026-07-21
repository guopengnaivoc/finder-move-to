-- 移动到… Quick Action
-- 把 Finder 选中项移动到用户选择的文件夹。
-- 若目标文件夹已存在同名文件/文件夹,弹框让用户选择:替换 / 两者都保留(自动改名)/ 跳过。
-- 可测试的纯逻辑处理器:hasConflict / uniqueName / moveOne(不弹窗,供自动化测试)。

on run {input, parameters}
	if input is {} then return input
	try
		set destFolder to (choose folder with prompt "移动到哪个文件夹?")
	on error number -128
		-- 用户取消,静默退出
		return input
	end try
	set failedMessages to {}
	repeat with anItem in input
		set srcAlias to my toAlias(anItem)
		set choice to "move"
		if my hasConflict(srcAlias, destFolder) then
			set nm to my baseName(srcAlias)
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
		set errMsg to my moveOne(srcAlias, destFolder, choice)
		if errMsg is not "" then set end of failedMessages to errMsg
	end repeat
	if (count of failedMessages) > 0 then
		set AppleScript's text item delimiters to return
		set report to (failedMessages as text)
		set AppleScript's text item delimiters to ""
		display dialog "有 " & (count of failedMessages) & " 项移动失败:" & return & report buttons {"好"} default button "好" with icon caution
	end if
	return input
end run

-- 把输入项(alias 或 POSIX 路径文本)统一成 alias
on toAlias(anItem)
	if class of anItem is text then
		return (POSIX file anItem) as alias
	else
		return anItem as alias
	end if
end toAlias

-- 取项目名(文件或文件夹)
on baseName(srcAlias)
	return do shell script "/usr/bin/basename " & quoted form of (POSIX path of srcAlias)
end baseName

-- 目标文件夹的 POSIX 路径(确保以 / 结尾)
on destPath(destFolder)
	set p to POSIX path of destFolder
	if p does not end with "/" then set p to p & "/"
	return p
end destPath

-- 目标里是否已存在同名项
on hasConflict(srcAlias, destFolder)
	set target to my destPath(destFolder) & my baseName(srcAlias)
	try
		do shell script "/bin/test -e " & quoted form of target
		return true
	on error
		return false
	end try
end hasConflict

-- 执行单项移动。choice: "move" | "replace" | "keepboth" | "skip"
-- 成功或跳过返回 "";失败返回错误信息文本。
on moveOne(srcAlias, destFolder, choice)
	if choice is "skip" then return ""
	try
		set nm to my baseName(srcAlias)
		set dp to my destPath(destFolder)
		if choice is "replace" then
			-- 把目标里已存在的同名项移到废纸篓(可恢复),再移动
			set existingAlias to (POSIX file (dp & nm)) as alias
			tell application "Finder" to delete existingAlias
			tell application "Finder" to move srcAlias to destFolder
		else if choice is "keepboth" then
			-- 自动改成不冲突的新名字后移动(mv -n 保证不覆盖)
			set newName to my uniqueName(dp, nm)
			do shell script "/bin/mv -n " & quoted form of (POSIX path of srcAlias) & " " & quoted form of (dp & newName)
		else
			tell application "Finder" to move srcAlias to destFolder
		end if
		return ""
	on error errMsg
		return errMsg
	end try
end moveOne

-- 在目标目录 dp 下为 baseName 生成不冲突的新名字,如 "foo 2.txt"、"foo 3.txt"
on uniqueName(dp, baseName)
	set {nm, ext} to my splitExt(baseName)
	set i to 2
	repeat
		if ext is "" then
			set candidate to nm & " " & (i as text)
		else
			set candidate to nm & " " & (i as text) & "." & ext
		end if
		try
			do shell script "/bin/test -e " & quoted form of (dp & candidate)
			set i to i + 1
		on error
			return candidate
		end try
	end repeat
end uniqueName

-- 把文件名拆成 {主名, 扩展名};无扩展名则扩展名为 ""
on splitExt(fname)
	if fname contains "." then
		set AppleScript's text item delimiters to "."
		set parts to text items of fname
		set ext to last item of parts
		set nm to (items 1 thru -2 of parts) as text
		set AppleScript's text item delimiters to ""
		return {nm, ext}
	else
		return {fname, ""}
	end if
end splitExt
