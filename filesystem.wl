import "disk.wl"

undecorated void^ memcpy(void^ dst, void^ src, ulong sz);
undecorated void^ memset(void^ dst, int c, ulong n);
undecorated char^ strncpy(char^ dst, char^ src, ulong n);
undecorated ulong time(ulong^ tloc);
undecorated int printf(char^ fmt, ...);

/*
void writeClusterHeader(void ^dst, ClusterHeader h) {
    memcpy(dst, &h, ClusterHeader.sizeof)
}*/

struct ClusterHeader {
    uint next
    uint eof

    this() {
        .next = 0
        .eof = ClusterHeader.sizeof
    }
}

const uint MAX_FILENAME = 11

const uint FILEATTR_FILE = 0x0
const uint FILEATTR_DIR = 0x1
const uint FILEATTR_HIDDEN = 0x2
const uint FILEATTR_READONLY = 0x4

const uint STREAM_TRUNCATE = 0x0
const uint STREAM_APPEND = 0x1

struct FileInfo {
    char[11] filename
    char attributes
    uint filesize
    uint startCluster
    uint creationTime
    uint modificationTime
    uint fileId

    this() {
        memset(.filename.ptr, 0, 11)
        .attributes = 0
        .filesize = 0
        .startCluster = 0
        .creationTime = 0
        .modificationTime = 0
        .fileId = 0
    }

    void print() {
        if(.attributes & FILEATTR_DIR) {
            printf("DIR: ")
        } else {
            printf("FILE: ")
        }

        printf("%.11s (%d) @%d", .filename, .filesize, .startCluster)

        printf("\n")
    }
}

struct StreamInfo {
    uint cluster
    uint offset //offset within cluster

    this(uint cluster) {
        .cluster = cluster
        .offset = ClusterHeader.sizeof
    }
}

struct BootBlock {
    char[512] padding
    char[8] fsType
    ushort sectorSize // in bytes
    ushort clusterSize // in sectors
    uint nclusters
    uint clusterTableLoc // location of first cluster in clusterTable
    uint fileTableLoc //location of first cluster in fileTable
    
    this() {
        memset(.padding.ptr, 0, 512)
        memset(.fsType.ptr, 0, 8)
        memcpy(.fsType.ptr, "WLFS".ptr, 4)
        .sectorSize = 0
        .clusterSize = 0
        .nclusters = 0
        .clusterTableLoc = 0
    }
}

class Filesystem {
    const uint SECTORS_PER_CLUSTER
    Disk disk

    BootBlock bootBlock

    this(Disk disk) {
        .disk = disk
        .SECTORS_PER_CLUSTER = 8
    }

    uint getFirstSectorOfCluster(uint cluster) {
        return cluster * .SECTORS_PER_CLUSTER
    }

    void writeClusterHeader(uint cluster, ClusterHeader head) {
        char[512] sector
        .disk.readSector(.getFirstSectorOfCluster(cluster), sector.ptr)
        memcpy(sector.ptr, &head, ClusterHeader.sizeof)
        .disk.writeSector(.getFirstSectorOfCluster(cluster), sector.ptr)
    }

    ClusterHeader readClusterHeader(uint cluster) {
        char[512] sector
        ClusterHeader header
        .disk.readSector(.getFirstSectorOfCluster(cluster), sector.ptr)
        memcpy(&header, sector.ptr, ClusterHeader.sizeof)
        return header
    }

    int write(void^ ptr, uint sz, StreamInfo^ stream) {
        char[512] sector

        .disk.readSector(.getFirstSectorOfCluster(stream.cluster), sector.ptr)
        ClusterHeader clusterHeader 
        memcpy(&clusterHeader, sector.ptr, ClusterHeader.sizeof)

        uint n = 0
        while(n < sz) {
            uint nwrite = sz - n
            //if(nwrite - stream.offset > 512) nwrite = 512 - stream.offset

            uint sectorn = stream.offset / 512
            uint sectoroff = stream.offset % 512
            .disk.readSector(.getFirstSectorOfCluster(stream.cluster) + sectorn, sector.ptr)
            memcpy(&sector[sectoroff], &ptr[n], nwrite)
            .disk.writeSector(.getFirstSectorOfCluster(stream.cluster) + sectorn, sector.ptr)

            n += nwrite
            stream.offset += nwrite

            if(stream.offset > 512 * .SECTORS_PER_CLUSTER) {
                clusterHeader.eof = 0
                if(clusterHeader.next == 0) {
                    clusterHeader.next = .clusterAlloc()
                }
                
                .writeClusterHeader(stream.cluster, clusterHeader)

                stream.cluster = clusterHeader.next
                stream.offset = ClusterHeader.sizeof
                .disk.readSector(.getFirstSectorOfCluster(stream.cluster), sector.ptr)
                memcpy(&clusterHeader, sector.ptr, ClusterHeader.sizeof)
            }
        }

        if(clusterHeader.next == 0 and stream.offset > clusterHeader.eof) {
            clusterHeader.eof = stream.offset
            .writeClusterHeader(stream.cluster, clusterHeader)
        }

        return sz
    }

    int read(void ^ptr, uint sz, StreamInfo^ stream) {
        char[512] sector

        .disk.readSector(.getFirstSectorOfCluster(stream.cluster), sector.ptr)
        ClusterHeader clusterHeader 
        memcpy(&clusterHeader, sector.ptr, ClusterHeader.sizeof)

        uint n = 0

        while(n < sz) {
            if(stream.offset >= clusterHeader.eof) return n

            int nread = sz - n
            if(nread - stream.offset > 512) nread = 512 - stream.offset % 512

            uint sectorn = stream.offset / 512
            uint sectoroff = stream.offset % 512
            .disk.readSector(.getFirstSectorOfCluster(stream.cluster) + sectorn, sector.ptr)
            memcpy(&ptr[n], &sector[sectoroff], nread)

            n += nread
            stream.offset += nread

            if(stream.offset > 512 * .SECTORS_PER_CLUSTER) {
                if(clusterHeader.next == 0) return n
                stream.cluster = clusterHeader.next
                stream.offset = ClusterHeader.sizeof
                .disk.readSector(.getFirstSectorOfCluster(stream.cluster), sector.ptr)
                memcpy(&clusterHeader, sector.ptr, ClusterHeader.sizeof)
            }
        }

        return n
    }

    uint seek(uint nbytes, StreamInfo ^stream) {
        char[512] sector
        .disk.readSector(.getFirstSectorOfCluster(stream.cluster), sector.ptr)
        ClusterHeader clusterHeader 
        memcpy(&clusterHeader, sector.ptr, ClusterHeader.sizeof)

        uint n = nbytes
        while(stream.offset + n > 512 * 8 - ClusterHeader.sizeof) {
            n -= ((512 * 8 - ClusterHeader.sizeof) - stream.offset)

            if(!clusterHeader.next) {
                clusterHeader.next = .clusterAlloc()
                printf("ALLOC CLUSTER\n")
            }

            stream.cluster = clusterHeader.next
        }

        stream.offset += n
    }

    BootBlock readBootBlock() {
        char[512] sector
        BootBlock bl
        char^ bootBlockPtr = char^: &bl

        int i = 0
        while(i * Disk.SECTOR_SIZE < BootBlock.sizeof) {
            int copySize = 512
            if((BootBlock.sizeof - (i * 512)) < 512) copySize = BootBlock.sizeof - i * 512
            .disk.readSector(i, sector.ptr)
            memcpy(&bootBlockPtr[i * Disk.SECTOR_SIZE], sector.ptr, copySize)
            i++
        }

        return bl
    }

    uint getRootId() {
        return 0
    }

    FileInfo getFileInfo(uint id) {
        char[512] sector
        uint cluster = .bootBlock.fileTableLoc

        FileInfo info
        StreamInfo stream = StreamInfo(cluster)
        .seek(ClusterHeader.sizeof + id * FileInfo.sizeof, &stream)
        .read(&info, FileInfo.sizeof, &stream)

        return info
    }

    void writeFileInfo(FileInfo info) {
        char[512] sector
        uint cluster = .bootBlock.fileTableLoc

        StreamInfo stream = StreamInfo(cluster)
        .seek(ClusterHeader.sizeof + info.fileId * FileInfo.sizeof, &stream)
        .write(&info, FileInfo.sizeof, &stream)
    }

    void writeBootBlock() {
        char[512] sector
        char^ bootBlockPtr = char^: &.bootBlock

        int i = 0
        while(i * Disk.SECTOR_SIZE < BootBlock.sizeof) {
            int copySize = 512
            if((BootBlock.sizeof - (i * .bootBlock.sectorSize)) < .bootBlock.sectorSize) copySize = BootBlock.sizeof - i * .bootBlock.sectorSize
            memcpy(sector.ptr, &bootBlockPtr[i * Disk.SECTOR_SIZE], copySize)
            .disk.writeSector(i, sector.ptr)
            i++
        }
    }

    void format() {
        //char[Disk.SECTOR_SIZE] sector
        .zeroCluster(0)
        .zeroCluster(1)
        .zeroCluster(2)

        char[512] sector
        memset(sector.ptr, 0, 512)

        .bootBlock = BootBlock()
        .bootBlock.sectorSize = Disk.SECTOR_SIZE
        .bootBlock.clusterSize = .SECTORS_PER_CLUSTER
        .bootBlock.nclusters = .disk.nsectors / .SECTORS_PER_CLUSTER
        .bootBlock.clusterTableLoc = 1
        .bootBlock.fileTableLoc = 2

        .writeBootBlock()

        // cluster table sector
        ClusterHeader header = ClusterHeader()
        .writeClusterHeader(1, header)

        // file table sector
        .writeClusterHeader(2, header)

        char c
        StreamInfo ctStream = StreamInfo(1)
        c = 0x11
        .write(&c, char.sizeof, &ctStream)
        c = 0x01
        .write(&c, char.sizeof, &ctStream)

        // create root dir
        FileInfo root = FileInfo()
        root.attributes = FILEATTR_DIR
        root.creationTime = time(null)
        root.modificationTime = root.creationTime
        root.startCluster = .clusterAlloc()

        .writeFileInfo(root)
    }

    StreamInfo open(FileInfo info, int flags) {
        char[512] sector
        uint cluster = info.startCluster
        uint offset = ClusterHeader.sizeof
        if(flags & STREAM_APPEND) {
            ClusterHeader header = .readClusterHeader(cluster)
            while(header.next) {
                cluster = header.next
                header = .readClusterHeader(cluster)
            }
            offset = header.eof
        }
        StreamInfo stream = StreamInfo(cluster)
        stream.offset = offset
        return stream
    }

    void zeroCluster(int cl) {
        int off = .getFirstSectorOfCluster(cl)
        char[512] sector
        memset(sector.ptr, 0, 512)
        for(int i = 0; i < .SECTORS_PER_CLUSTER; i++) {
            .disk.writeSector(off + i, sector.ptr)
        }
    }

    int clusterAlloc() {
        char[512] sector
        int sectorid = .getFirstSectorOfCluster(.bootBlock.clusterTableLoc)
        .disk.readSector(sectorid, sector.ptr)
        ClusterHeader^ head = void^: &sector[0]

        int clusterId = -1
        for(int i = ClusterHeader.sizeof; i < .bootBlock.sectorSize; i++) {
            if((sector[i] & 0x0f) == 0) {
                sector[i] |= 0x01
                .disk.writeSector(sectorid, sector.ptr)
                clusterId = (i - ClusterHeader.sizeof) * 2
                break
            }

            if((sector[i] & 0xf0) == 0) {
                sector[i] |= 0x10
                .disk.writeSector(sectorid, sector.ptr)
                clusterId = (i - ClusterHeader.sizeof) * 2 + 1
                break
            }
        }

        if(clusterId > 0) {
            memset(sector.ptr, 0, 512)
            ClusterHeader header = ClusterHeader()
            header.eof = ClusterHeader.sizeof
            memcpy(sector.ptr, &header, ClusterHeader.sizeof)
            .disk.writeSector(.getFirstSectorOfCluster(clusterId), sector.ptr)
        }

        return clusterId
    }

    uint nextFreeFileId() {
        StreamInfo stream = StreamInfo(.bootBlock.fileTableLoc)

        FileInfo info
        uint id = 0
        while(true) {
            uint n = .read(&info, FileInfo.sizeof, &stream)
            if(info.filesize == 0 and info.startCluster == 0) {
                break
            }
            if(n == 0) {
                break
            }
            id++
        }
        return id
    }

    FileInfo fileAlloc(char ^filenm, int attributes) {
        FileInfo info = FileInfo()
        strncpy(info.filename.ptr, filenm, 11)
        info.attributes = attributes
        info.filesize = 0
        info.startCluster = .clusterAlloc()
        info.creationTime = time(null)
        info.modificationTime = info.creationTime
        info.fileId = .nextFreeFileId()

        return info
    }

    void dump(uint fileId, int indent) {
        for(int i = 0; i < indent; i++) {
            printf("  ");
        }

        FileInfo info = .getFileInfo(fileId)
        printf("%.11s", info.filename.ptr)
        if(info.attributes & FILEATTR_DIR) printf("/")
        printf("\n")
        if(info.attributes & FILEATTR_DIR) {
            StreamInfo stream = StreamInfo(info.startCluster)
            int child = -1
            while(.read(&child, uint.sizeof, &stream)) {
                if(child < 0) break
                .dump(child, indent + 1)
            }
        }
    }

    void print() {
        .dump(0, 0)
    }

    int deallocCluster(int clusterid) {
        char[512] sector
        .disk.readSector(.getFirstSectorOfCluster(clusterid), sector.ptr)
        ClusterHeader head
        memcpy(&head, sector.ptr, ClusterHeader.sizeof)
        
        if(head.next > 0) .deallocCluster(head.next)

        StreamInfo stream = StreamInfo(.bootBlock.clusterTableLoc)
        .seek(clusterid / 2, &stream)
        StreamInfo peek = stream
        char c
        .read(&c, 1, &peek)
        if(clusterid % 2) {
            c = c & 0xf0
        } else {
            c = c & 0x0f
        }
        .write(&c, 1, &stream)
    }

    void deallocFile(int fileid) {
        FileInfo info = .getFileInfo(fileid)
        if(info.attributes & FILEATTR_DIR) {
            StreamInfo stream = StreamInfo(info.startCluster)
            int child = -1
            while(.read(&child, uint.sizeof, &stream)) {
                if(child > 0) {
                    .deallocFile(child)
                }
            }
        }
        .deallocCluster(info.startCluster)
    }

    void appendToDirectory(FileInfo directory, FileInfo file) {
        StreamInfo stream = .open(directory, STREAM_APPEND)
        .write(&file.fileId, uint.sizeof, &stream)
        .writeFileInfo(file)
    }

    void remove(uint parent, uint child) {
        char[512] sector
        FileInfo parentInfo = .getFileInfo(parent)
        if(!(parentInfo.attributes & FILEATTR_DIR)) return

        StreamInfo stream = StreamInfo(parentInfo.startCluster)
        StreamInfo peek = stream
        uint dirent = -1
        while(.read(&dirent, int.sizeof, &peek)) {
            if(dirent == child) {
                dirent = 0xffffffff
                .write(&dirent, int.sizeof, &stream)
            }
            stream = peek
        }

        .deallocFile(child)
    }

    uint create(uint parent, char^ filenm, char attributes) {
        char[512] sector

        FileInfo parentInfo = .getFileInfo(parent)
        if(!(parentInfo.attributes & FILEATTR_DIR)) return -1

        FileInfo info = .fileAlloc(filenm, attributes)
        .writeFileInfo(info)

        .appendToDirectory(parentInfo, info)

        return info.fileId
    }
}
