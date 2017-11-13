all: tm.1

tm.1: tm
	pod2man tm tm.1

clean:
	-rm tm.1

.PHONY: all clean
