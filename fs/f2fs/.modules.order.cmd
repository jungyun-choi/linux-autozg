cmd_fs/f2fs/modules.order := {  :; } | awk '!x[$$0]++' - > fs/f2fs/modules.order
