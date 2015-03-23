import "disk.wl"
import "filesystem.wl"

use "importc"
import(C) "stdio.h"
import(C) "string.h"

uint pwd = 0
Filesystem fs

int mkdir(char^ filenm) {
    return fs.create(pwd, filenm, FILEATTR_DIR)
}

int touch(char^ filenm) {
    return fs.create(pwd, filenm, FILEATTR_FILE)
}

int listdir() {
    FileInfo dirInfo = fs.getFileInfo(pwd)

    if(!(dirInfo.attributes & FILEATTR_DIR)) {
        printf("file '%.11s' is not a directory\n", dirInfo.filename)
        return 0
    }

    StreamInfo stream = StreamInfo(dirInfo.startCluster)

    int child = -1
    while(fs.read(&child, int.sizeof, &stream) > 0) {
        if(child > 0) {
            FileInfo info = fs.getFileInfo(child)
            printf("%.11s\n", info.filename)
        }
    }
    return 0
}

int pwdChildId(char^ filenm) {
    int len = strnlen(filenm, 11)
    FileInfo dirInfo = fs.getFileInfo(pwd)

    if(!(dirInfo.attributes & FILEATTR_DIR)) {
        printf("file '%.11s' is not a directory\n", dirInfo.filename)
        return -1
    }

    if(!strncmp(filenm, "/", 11)) {
        return 0 
    }

    StreamInfo stream = StreamInfo(dirInfo.startCluster)

    int child = -1
    while(fs.read(&child, int.sizeof, &stream) > 0) {
        FileInfo info = fs.getFileInfo(child)
        if(!strncmp(filenm, info.filename, len)) {
            return info.fileId
        }
    }

    printf("file not found: %.11s\n", filenm)
    return -1
}

int chdir(char^ filenm) {

    int child = pwdChildId(filenm)

    if(child >= 0) {
        pwd = child
    }

    return -1
}

int print(uint fileid) {
    FileInfo info = fs.getFileInfo(fileid)
    StreamInfo stream = StreamInfo(info.startCluster)
    char c
    while(fs.read(&c, char.sizeof, &stream) > 0) {
        printf("%c", c)
    }
    printf("\n")
}

void prompt() {
    char[128] linebuf
    uint n = 0
    while(true) {
        printf(">> ")

        n = 0
        while(n < 128) {
            int c = getchar()
            if(c == '\n') break
            linebuf[n] = c
            n++
        }
        linebuf[n] = 0

        if(!strncmp(linebuf.ptr, "exit", 4)) {
            return
        } else if(!strncmp(linebuf.ptr, "dump", 4)) {
            fs.print()
        } else if(!strncmp(linebuf.ptr, "ls", 2)) {
            listdir()
        } else if(!strncmp(linebuf.ptr, "cd ", 3)) {
            chdir(&linebuf[3])
        } else if(!strncmp(linebuf.ptr, "mkdir ", 6)) {
            int fileid = fs.create(pwd, &linebuf[6], FILEATTR_DIR)
            if(fileid < 0) {
                printf("error creating new file\n")
            }
        } else if(!strncmp(linebuf.ptr, "touch ", 6)) {
            int fileid = fs.create(pwd, &linebuf[6], FILEATTR_FILE)
            if(fileid < 0) {
                printf("error creating new file\n")
            }
        } else if(!strncmp(linebuf.ptr, "rm ", 3)) {
            int id = pwdChildId(&linebuf[3])
            if(id > 0) fs.remove(pwd, id)
        } else if(!strncmp(linebuf.ptr, "export ", 7)) {
            printf("saving disk as %s\n", linebuf.ptr)
            fs.disk.export(&linebuf[7])
        } else if(!strncmp(linebuf.ptr, "print ", 6)) {
            int id = pwdChildId(&linebuf[6])
            print(id)
        } else if(!strncmp(linebuf.ptr, "write ", 6)) {
            int id = pwdChildId(&linebuf[6])
            
            if(id < 0) {
                continue
            }

            StreamInfo stream = fs.open(fs.getFileInfo(id), 0)

            n = 0
            while(n < 128) {
                int c = getchar()
                if(c == '\n') break
                linebuf[n] = c
                n++
            }
            linebuf[n] = 0
            
            fs.write(linebuf.ptr, strnlen(linebuf, 128), &stream)
        }
    }
}

int main(int argc, char^^ argv) {
    Disk disk = new Disk(2048)
    fs = new Filesystem(disk)
    fs.format()
    uint root = fs.getRootId()
    uint dir1 = fs.create(root, "dir", FILEATTR_DIR)
    fs.create(root, "somefile", FILEATTR_FILE)
    fs.create(dir1, "secretFile", FILEATTR_FILE)
    disk.export("disk.wlfs")

    prompt()

    return 0
}
