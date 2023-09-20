# What AutoZG Does
AutoZG is a dynamic zone group management scheme within the F2FS file system designed to maximize performance while minimizing Write Amplification Factor(WAF) based on the characteristics of the workload.

To achieve this, AutoZG predicts the lifespan of data being written by applications running on the host, organizes write streams accordingly, and stores each stream in individual zone groups. Furthermore, it analyzes the hotness of write streams and determines the size of zone groups proportionally to their hotness, thus optimizing overall performance while minimizing WAF. Additionally, it identifies chip information for the internal mapping of zones in ZNS SSDs to maximize chip parallelism and group zones accordingly.

# Prerequisites
AutoZG has been implemented in Linux kernel version 5.19-rc5. To use it, you should first install this specific Linux kernel version. After that, you can replace certain source code files with those from github to incorporate AutoZG into your kernel.

# About Source Code
To implement AutoZG in the Linux kernel source code, the modifications can be broadly categorized into three main parts.

## Support Zone Grouping Scheme in F2FS file system
The F2FS file system aggregates data at the segment level and forwards it to the block device layer. When mounting with a ZNS SSD as the device, it operates by opening one zone at a time, and when that zone becomes full, it searches for a new free zone to open. Consequently, when using a small-zone ZNS SSD where one zone is mapped to one chip, the performance significantly degrades upon mounting.

To address this issue, AutoZG opens and interleaves access to a group of zones, equivalent to the zone group size, when searching for the next segment to store data. This ensures chip parallelism is maintained. Furthermore, the file system's internal garbage collection (GC) process traditionally reclaims one zone at a time, leading to performance bottlenecks. To mitigate this, modifications were made to enable parallel processing of GC.

The following provides explanations of the source code changes made to implement AutoZG.

### fs/f2fs/segment.c
The source code contains all the functions necessary for F2FS to handle data at the segment level. We have made modifications to the following functions to differentiate write requests from the host into streams and allocate zone groups with varying sizes and configurations for each stream.

### fs/f2fs/gc.c
In the source code, the existing logic performs garbage collection (GC) by reclaiming victim zones when the number of free zones falls below a certain threshold. You've made modifications to this code to enable parallel zone reclamation during GC on small-zone SSDs.

### fs/f2fs/f2fs.h
In AutoZG, you've added defines and variables necessary for its operation within the F2FS source code. These variables have been declared within the superblock information (SBI) data structure. Here's a general description of what these additions might look like:

## Support Non-po2 ZNS SSD
In Kernel version 5.19-rc5, there is an issue where non-power-of-two ZNS SSDs cannot be mounted. To address this, the following files have been modified to recognize non-power-of-two devices.

- block/blk-mq.c
- block/blk-zoned.c
- drivers/nvme/host/zns.c
- includes/linux/blkdev.h

## Support More WLTH Values (Optional)

The Write Lifetime Hint (WLTH) values provided by the Linux kernel consist of a total of 6 options. Among these, 4 values, namely Short, Medium, Long, and Extreme, are used to express write hotness levels. The experimental results in the paper were obtained using only these 4 WLTH values. However, in order to conduct further experiments with a more granular WLTH division, enum values have been added by modifying the following files

- fs/fcntl.c
- include/linux/fs.h
  
# How To Use
```
git clone "AutoZG github address"

# copy all files included to linux 5.19-rc5 source code

# open fs/f2fs/f2fs.h to configure AutoZG
# USE_STRIPE 1, USE_STREAM 1, MULTI_16 0, MULTI_48 0, ALL_FULL 0 ==> AutoZG
# USE_STRIPE 1, USE_STREAM 1, MULTI_16 1, MULTI_48 0, ALL_FULL 0 ==> 16-Multi
# USE_STRIPE 1, USE_STREAM 1, MULTI_16 0, MULTI_48 1, ALL_FULL 0 ==> 48-Triple
# USE_STRIPE 1, ALL_FULL 1 ==> Max-Grouping

make -j 'proc' && install
```
