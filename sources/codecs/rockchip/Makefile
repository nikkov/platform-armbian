obj-m := i2s_clock_board.o

all:
	make -C /lib/modules/$(shell uname -r)/build M=$(PWD) modules

clean:
	make -C /lib/modules/$(shell uname -r)/build M=$(PWD) clean

install:
	sudo cp i2s_clock_board.ko /lib/modules/$(shell uname -r)/kernel/sound/soc/codecs
	sudo depmod -a
