undecorated void^ memcpy(void^ dst, void^ src, ulong n);

use "importc"
import(C) "stdio.h"
import(C) "string.h"

class Disk {
    static const int SECTOR_SIZE = 512

    int nsectors
    char^ data

    this(int nsector) {
        .nsectors = nsector
        .data = new char[nsector * .SECTOR_SIZE]
        memset(.data, 0, nsector * .SECTOR_SIZE)
    }

    ~this() {
        delete .data
    }

    void readSector(int i, char^ sData) {
        char^ sector = char^: &.data[i * .SECTOR_SIZE]
        memcpy(sData, sector, .SECTOR_SIZE)
    }

    void writeSector(int i, char^ sData) {
        char^ sector = char^: &.data[i * .SECTOR_SIZE]
        memcpy(sector, sData, .SECTOR_SIZE)
    }

    void export(char^ filename) {
        FILE^ file = fopen(filename, "wb".ptr)
        fwrite(.data, .SECTOR_SIZE, .nsectors, file)
        fclose(file)
    }
} 
