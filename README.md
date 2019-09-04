# Embedded Develop Tools

EDT provide a bundle of develop tools run on embedded devices.

- [binutils](https://www.gnu.org/software/binutils/)
- [gdb](https://www.gnu.org/s/gdb/)
- [strace](https://strace.io/)
- [ltrace](https://github.com/dkogan/ltrace)
- [valgrind](http://valgrind.org/)
- [gperftools](https://github.com/gperftools/gperftools)
- [heaptrack](https://github.com/KDE/heaptrack)
- [tcpdump](https://github.com/the-tcpdump-group/tcpdump)
- [elfutils](https://sourceware.org/git/?p=elfutils.git)
- [systemtap](https://sourceware.org/git/?p=systemtap.git)

## Build

1. Setup toolchains

```sh
$ export PATH=/opt/gcc_aarch64-linux-gnu/bin/:$PATH
```
2. Run build.sh

```sh
$ bash build.sh -h aarch64-linux-gnu -j 32
```

3. Check packed files

```sh
$ find _install -name '*edt-*.tar.gz'
```
