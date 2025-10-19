/*
 * POSIX 共有メモリとセマフォを扱うブリッジ実装
 */
#include "FmoBridge.h"
#include <errno.h>

/* 名前付き共有メモリを開き、指定サイズに拡張する */
/*
 * 名前付き共有メモリを開き、指定サイズに拡張する。
 * Windows の FMO に近づけるため、生成後すぐに unlink して
 * クラッシュ時に残骸が残らないようにする。
 */
int fmo_open_shared(const char *name, size_t size) {
    int fd = shm_open(name, O_CREAT | O_RDWR, 0666);
    if (fd == -1) {
        return -1;
    }
    if (ftruncate(fd, size) == -1) {
        close(fd);
        return -1;
    }
    /* エフェメラル運用のため直後に名前を削除 */
    shm_unlink(name);
    return fd;
}

/* 共有メモリをマップする */
void *fmo_map(int fd, size_t size) {
    return mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
}

/* ftruncate の薄いラッパー */
int fmo_ftruncate(int fd, size_t size) {
    return ftruncate(fd, size);
}

/* fd をクローズする */
int fmo_close_fd(int fd) {
    return close(fd);
}

/* 名前付き共有メモリを削除する */
int fmo_shm_unlink(const char *name) {
    return shm_unlink(name);
}

/* マッピングを解除する */
int fmo_munmap(void *addr, size_t size) {
    return munmap(addr, size);
}

/* 名前付きセマフォを開く */
sem_t *fmo_sem_open(const char *name, int oflag, mode_t mode, unsigned int value) {
    return sem_open(name, oflag, mode, value);
}

/* セマフォ待機 */
int fmo_sem_wait(sem_t *sem) {
    return sem_wait(sem);
}

/* セマフォをノンブロッキングで取得 */
int fmo_sem_trywait(sem_t *sem) {
    return sem_trywait(sem);
}

/* セマフォ解放 */
int fmo_sem_post(sem_t *sem) {
    return sem_post(sem);
}

/* セマフォをクローズ */
int fmo_sem_close(sem_t *sem) {
    return sem_close(sem);
}

/* セマフォを削除 */
int fmo_sem_unlink(const char *name) {
    return sem_unlink(name);
}

/*
 * 他のベースウェアが起動しているかを判定する (ninix仕様準拠)
 * shm_open(name, O_RDWR, 0) が成功するかで判定
 * 戻り値: 1=起動中, 0=起動していない, -1=エラー
 */
int fmo_check_running(const char *shm_name) {
    int fd = shm_open(shm_name, O_RDWR, 0);
    if (fd == -1) {
        if (errno == ENOENT) {
            /* 共有メモリが存在しない = 起動していない */
            return 0;
        }
        /* その他のエラー */
        return -1;
    }
    /* 開けた = 既に起動している */
    close(fd);
    return 1;
}

/*
 * 既存の共有メモリを開く (読み書きモード)
 * 新規作成はしない
 */
int fmo_open_existing_shared(const char *name) {
    return shm_open(name, O_RDWR, 0);
}
