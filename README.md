# What AutoZG Does
AutoZG is a dynamic zone group management scheme within the F2FS file system designed to maximize performance while minimizing Write Amplification Factor(WAF) based on the characteristics of the workload.. 

To achieve this, AutoZG predicts the lifespan of data being written by applications running on the host, organizes write streams accordingly, and stores each stream in individual zone groups. Furthermore, it analyzes the hotness of write streams and determines the size of zone groups proportionally to their hotness, thus optimizing overall performance while minimizing WAF. Additionally, it identifies chip information for the internal mapping of zones in ZNS SSDs to maximize chip parallelism and group zones accordingly.

# Prerequisites
AutoZG has been implemented in Linux kernel version 5.18-rc5. To use it, you should first install this specific Linux kernel version. After that, you can replace certain source code files with those from https://github.com/jungyun-choi/linux-autozg.git to incorporate AutoZG into your kernel.

# About Source Code
To implement AutoZG in the Linux kernel source code, the modifications can be broadly categorized into three main parts.

## Support Zone Grouping Scheme in F2FS file system
F2FS File system은 segment 단위로 데이터를 모아 block device layer로 전달한다. ZNS SSD를 device로 mount하는 경우, 한 번에 하나의 zone을 open하고 해당 zone이 full이 되면 새로운 free zone을 찾아서 open하는 방식으로 돌아간다. 이로 인해 zone하나가 chip 하나에 매핑되는 small-zone ZNS SSD의 경우 mount시 성능이 크게 떨어지게 된다. 이에 AutoZG는 data를 저장하기 위한 next segment를 찾을 때에 zone group 크기 만큼의 zone을 찾아 open하고 이들을 interleaving하게 access하여 chip-parallism을 확보하였다. 또한, file system이 자체적으로 수행하는 garbage collection(GC) 시에도 한 번에 하나의 zone씩 reclaim하기 때문에 성능이 크게 떨어지는 문제가 있어, GC도 병렬적으로 처리할 수 있도록 수정하였다. 다음은 AutoZG를 구현하기 위해 수정한 source code별 설명이다.

### fs/f2fs/segment.c
해당 source code에는 F2FS가 segment 단위로 data를 처리하기 위한 모든 함수들이 포함되어 있다. 우리는 아래의 함수들을 수정하여 host로부터 전달되는 write request를 stream으로 구분하고, stream 별로 서로 다른 크기와 구성을 갖는 zone group을 할당하도록 하였다.

- f2fs_allocate_data_block(...)
  - 해당 함수는 host로부터 전달된 data pages를 저장하기 위한 data block을 선택한다. 이를 위해 우선 연속된 block address로 구성된 새로운 segment를 찾고 그 segment를 다 채우면 또다시 새로운 segment를 찾는 과정을 반복한다. 우리는 해당 함수에서 새로운 segment를 찾을 때 마다 논문에 설명된 SFR 알고리즘을 통해 write stream을 구분할 수 있도록 수정하였다. 그리고 실제로 data를 저장하기 위한 new segment를 선택하는 get_new_segment() 함수에 stream_id를 인자로 넣어주어 stream 별로 서로 다른 zone에 위치한 segment에 data를 저장할 수 있게 하였다. 또한, 구분 된 stream의 hotness에 비례하도록 zone group 크기를 결정하는 동작도 해당 함수에 구현되었다.
  
- get_new_segment(...)
  - 기존 함수에서는 단순히 하나의 free zone을 bitmap에서 찾아 open하고 해당 zone의 모든 segment가 채워지면 또 다른 free zone을 찾는 것을 반복하게 구현되어있다. AutoZG에서는 해당 함수에서 stream ID를 인자로 받아 stream 별로 서로 다른 free zone을 찾는다. 그리고 f2fs_allocate_data_block() 함수에서 stream 마다 결정한 zone group의 크기만큼의 zone들을 group으로 묶어 open한다. Zone을 Grouping 할 때에는 각각의 zone이 내부적으로 매핑되는 chip을 확인하고 같은 chip에 접근하지 않도록 한다. Zone group의 크기는 각 stream이 저장하는 zone group 하나가 모두 full이 되면 새롭게 반영될 수 있다.

- init_free_segmap(...)
  - 해당 함수는 segment 관련하여 초기화를 해주는 역할을 한다. 우리는 해당 함수에서 zone group에 대한 정보를 저장하기 위해 추가한 변수들을 초기화하도록 하였다. 

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
  
