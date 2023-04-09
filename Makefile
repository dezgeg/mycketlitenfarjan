farjan.com: farjan.asm
	nasm $< -fbin -o $@
	@wc -c $@

.PHONY: run
run: farjan.com
	dosbox -conf dosbox-0.74-3.conf farjan.com
