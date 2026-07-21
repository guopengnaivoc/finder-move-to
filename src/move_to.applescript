-- 移动到… Quick Action
-- input: Finder 传入的选中项(alias 列表);parameters: 未使用
-- 行为:弹出文件夹选择框,把选中项移动(非复制)到目标文件夹

on run {input, parameters}
	if input is {} then return input
	set destFolder to missing value
	try
		set destFolder to (choose folder with prompt "移动到哪个文件夹?")
	on error number -128
		-- 用户取消,静默退出
		return input
	end try
	set failedMessages to moveItems(input, destFolder)
	if (count of failedMessages) > 0 then
		set AppleScript's text item delimiters to return
		set report to (failedMessages as text)
		set AppleScript's text item delimiters to ""
		display dialog "有 " & (count of failedMessages) & " 项移动失败:" & return & report buttons {"好"} default button "好" with icon caution
	end if
	return input
end run

-- 把 itemList 中每一项移动到 destFolder;返回失败信息列表(可自动化测试)
on moveItems(itemList, destFolder)
	set failedMessages to {}
	repeat with anItem in itemList
		try
			if class of anItem is text then
				set theAlias to (POSIX file anItem) as alias
			else
				set theAlias to anItem as alias
			end if
			tell application "Finder" to move theAlias to destFolder
		on error errMsg
			set end of failedMessages to errMsg
		end try
	end repeat
	return failedMessages
end moveItems
