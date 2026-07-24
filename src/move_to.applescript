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

	-- 先筛出真正要移动的项(排除已在目标文件夹里的),并统计其中同名冲突个数
	set toMove to {}
	repeat with anItem in input
		set p to my toPosix(anItem)
		if not my isSameFolder(p, dd) then set end of toMove to p
	end repeat
	set conflictCount to 0
	repeat with k from 1 to count of toMove
		if my hasConflict(item k of toMove, dd) then set conflictCount to conflictCount + 1
	end repeat

	set applyAll to false
	set savedChoice to "skip"
	set askedApplyAll to false
	set failed to {}
	repeat with k from 1 to count of toMove
		set srcPosix to item k of toMove
		set choice to "move"
		if my hasConflict(srcPosix, dd) then
			if applyAll then
				set choice to savedChoice
			else
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
				-- 还有多个同名项时,只问一次:其余是否统一按同样方式处理
				if (conflictCount > 1) and (not askedApplyAll) then
					set askedApplyAll to true
					try
						set ans to button returned of (display dialog "其余同名项也都用「" & btn & "」处理吗?" buttons {"否,逐个问", "是,全部这样"} default button "是,全部这样" with icon note)
					on error number -128
						set ans to "否,逐个问"
					end try
					if ans is "是,全部这样" then
						set applyAll to true
						set savedChoice to choice
					end if
				end if
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

-- 源项目所在的父文件夹(以 / 结尾)
on parentDir(srcPosix)
	return (do shell script "/usr/bin/dirname " & quoted form of srcPosix) & "/"
end parentDir

-- 源项目是否已经在目标文件夹里
on isSameFolder(srcPosix, dd)
	return (my parentDir(srcPosix)) is dd
end isSameFolder

-- 某 POSIX 路径是否存在
on pathExists(posixPath)
	try
		do shell script "/bin/test -e " & quoted form of posixPath
		return true
	on error
		return false
	end try
end pathExists

-- 目标里是否已存在同名项
on hasConflict(srcPosix, dd)
	return my pathExists(dd & my baseName(srcPosix))
end hasConflict

-- 执行单项移动。choice: "move" | "replace" | "keepboth" | "skip"
-- 成功或跳过返回 "";失败返回错误信息文本。绝不弹密码:失败即返回错误由上层汇总提示。
on moveOne(srcPosix, dd, choice, trashDir)
	if choice is "skip" then return ""
	try
		set nm to my baseName(srcPosix)
		if choice is "replace" then
			-- 旧的先移入废纸篓(可恢复);若废纸篓已有同名,改成不冲突的名字
			set trashName to nm
			if my pathExists(trashDir & nm) then set trashName to my uniqueName(trashDir, nm)
			do shell script "/bin/mv " & quoted form of (dd & nm) & " " & quoted form of (trashDir & trashName)
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
		if not (my pathExists(dir & candidate)) then return candidate
		set i to i + 1
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
