#ifndef FMO_BRIDGE_H
#define FMO_BRIDGE_H
/*
 * POSIX の共有メモリとセマフォを Swift から利用するための
 * シンプルな C ラッパー関数群です。各関数は対応する libc
 * 関数をそのまま呼び出します。
 */
#include <semaphore.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdint.h>

int fmo_open_shared(const char *name, size_t size);
void *fmo_map(int fd, size_t size);
int fmo_ftruncate(int fd, size_t size);
int fmo_close_fd(int fd);
int fmo_shm_unlink(const char *name);
int fmo_munmap(void *addr, size_t size);

/* セマフォ操作用ラッパー */
sem_t *fmo_sem_open(const char *name, int oflag, mode_t mode, unsigned int value);
int fmo_sem_wait(sem_t *sem);
int fmo_sem_trywait(sem_t *sem);
int fmo_sem_post(sem_t *sem);
int fmo_sem_close(sem_t *sem);
int fmo_sem_unlink(const char *name);

#endif
