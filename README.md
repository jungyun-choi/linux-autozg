# What AutoZG Does
AutoZG is a dynamic zone group management scheme within the F2FS file system designed to maximize performance while minimizing Write Amplification Factor(WAF) based on the characteristics of the workload.. 

To achieve this, AutoZG predicts the lifespan of data being written by applications running on the host, organizes write streams accordingly, and stores each stream in individual zone groups. Furthermore, it analyzes the hotness of write streams and determines the size of zone groups proportionally to their hotness, thus optimizing overall performance while minimizing WAF. Additionally, it identifies chip information for the internal mapping of zones in ZNS SSDs to maximize chip parallelism and group zones accordingly.

# Prerequisites
AutoZG has been implemented in Linux kernel version 5.18-rc5. To use it, you should first install this specific Linux kernel version. After that, you can replace certain source code files with those from github to incorporate AutoZG into your kernel.

# About Source Code
To implement AutoZG in the Linux kernel source code, the modifications can be broadly categorized into three main parts.

## Support Zone Grouping Scheme in F2FS file system
F2FS File system은 segment 단위로 데이터를 모아 block device layer로 전달한다. ZNS SSD를 device로 mount하는 경우, 한 번에 하나의 zone을 open하고 해당 zone이 full이 되면 새로운 free zone을 찾아서 open하는 방식으로 돌아간다. 이로 인해 zone하나가 chip 하나에 매핑되는 small-zone ZNS SSD의 경우 mount시 성능이 크게 떨어지게 된다. 이에 AutoZG는 data를 저장하기 위한 next segment를 찾을 때에 zone group 크기 만큼의 zone을 찾아 open하고 이들을 interleaving하게 access하여 chip-parallism을 확보하였다. 또한, file system이 자체적으로 수행하는 garbage collection(GC) 시에도 한 번에 하나의 zone씩 reclaim하기 때문에 성능이 크게 떨어지는 문제가 있어, GC도 병렬적으로 처리할 수 있도록 수정하였다. 다음은 AutoZG를 구현하기 위해 수정한 핵심 source code에 대한 설명이다.

### fs/f2fs/segment.c
해당 source code에는 F2FS가 segment 단위로 data를 처리하기 위한 모든 함수들이 포함되어 있다. 우리는 아래의 함수들을 수정하여 host로부터 전달되는 write request를 stream으로 구분하고, stream 별로 서로 다른 크기와 구성을 갖는 zone group을 할당하도록 하였다.

### fs/f2fs/gc.c
해당 source code에서는 free zone이 일정 수준 이하로 떨어지면 victim zone을 reclaim하는 GC를 수행한다. 우리는 small-zone SSD에서 GC시 zone을 병렬적으로 reclaim하기 위해 해당 code를 수정하였다. 

### fs/f2fs/f2fs.h
AutoZG에서 필요한 define과 mount하는 동안 유지해야하는 변수들을 해당 code에 선언하였다. 변수는 모두 superblock information(SBI) 자료구조에 추가하였다.

## Support Non-po2 ZNS SSD
Kernel 5.18-rc5 version에서는 zone size가 power of two 가 아닌 ZNS SSD를 mount할 수 없는 문제가 있다. 이를 해결하기 위해 다음의 file들을 수정하여 non-po2 device를 인식할 수 있도록 하였다. 

- block/blk-mq.c
- block/blk-zoned.c
- drivers/nvme/host/zns.c
- includes/linux/blkdev.h

## Support More WLTH Values (Optional)
Linux kernel에서 제공하는 Write Lifetime Hint(WLTH) 값은 총 6개가 제공되며, 그 중  write hotness를 표현할 수 있는 값은 Short, Medium, Long, Extreme으로 4개이다. 논문의 실험결과는 해당 4개의 값으로만 WLTH를 사용하여 도출하였으나, 추가적으로 WLTH를 세부적으로 나누어 실험하기 위해 아래 files를 수정하여 enum 값을 추가하였다.

- fs/fcntl.c
- include/linux/fs.h
  
# How To Use
```
git clone "AutoZG github address"

# copy all files included to linux 5.18-rc5 source code

# open fs/f2fs/f2fs.h to configure AutoZG
# USE_STRIPE 1, USE_STREAM 1, MULTI_16 0, MULTI_48 0, ALL_FULL 0 ==> AutoZG
# USE_STRIPE 1, USE_STREAM 1, MULTI_16 1, MULTI_48 0, ALL_FULL 0 ==> 16-Multi
# USE_STRIPE 1, USE_STREAM 1, MULTI_16 0, MULTI_48 1, ALL_FULL 0 ==> 48-Triple
# USE_STRIPE 1, ALL_FULL 1 ==> Max-Grouping

make -j 'proc' && install
```
