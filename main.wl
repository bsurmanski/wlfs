import "disk.wl"
import "filesystem.wl"

int main(int argc, char^^ argv) {
    Disk disk = new Disk(2048)
    Filesystem fs = new Filesystem(disk)
    fs.format()
    uint root = fs.getRootId()
    uint dir1 = fs.create(root, "dir", FILEATTR_DIR)
    fs.create(root, "somefile", FILEATTR_FILE)
    fs.create(dir1, "secretFile", FILEATTR_FILE)
    fs.dump(root, 0)
    disk.export("disk.wlfs".ptr)
    return 0
}
