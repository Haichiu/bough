tell application "System Events"
  tell (first process whose name is "MindFlow")
    set tabCh to character id 9
    try
      set w to first window whose name contains " – "
    on error
      set w to window 1
    end try
    set els to {w} & (entire contents of w)
    set out to {}
    repeat with el in els
      set r to ""
      set p to {0, 0}
      set v to ""
      set t to ""
      set dsc to ""
      try
        set r to role of el as text
      end try
      try
        set p to position of el
      end try
      try
        set vv to value of el
        if class of vv is text then set v to vv
      end try
      try
        set t to title of el as text
      end try
      try
        set dsc to description of el as text
      end try
      set end of out to r & tabCh & ((item 1 of p) as text) & tabCh & ((item 2 of p) as text) & tabCh & v & tabCh & t & tabCh & dsc
    end repeat
  end tell
end tell
set AppleScript's text item delimiters to linefeed
return out as text
