# WLFS
## A Simple Filesystem Emulation
vaguely based off of the FAT, and EXT4 Filesystems.

Written in the [OWL programming language](https://www.github.com/bsurmanski/wlc).

## Structure

512 bytes: superblock padding

    Cluster 0 (offset 512): Boot Superblock
    Cluster \*: Cluster Table (first cluster sector)
    Cluster \*: file list
    Cluster \*: Data sectors

### Clusters
Clusters are a contiguous allocation unit of disk space. A cluster spans
multiple sectors. Every cluster (except the first cluster) contains a cluster
header as it's first entry.

#### Cluster Header

    4 byte: previous cluster
    4 byte: next cluster
    4 byte: eof
    4 byte: padding

previous cluster: the previous cluster in the cluster
next cluster: the next cluster in the cluster
eof: the byte within the cluster in which the file ends.

If previous, next, is zero, then there is no previous or next cluster in the
file.
eof should be sizeof(CLUSTER) unless next cluster is non-zero
Every sector except the superblock has a cluster header.

### Boot Superblock
contains boot information
Only cluster that does not have a cluster header

    512 byte: padding (for boot sector, etc)
    8 bytes: FileSystem type identifier ("WLFS")
    2 bytes: bytes per sector
    2 bytes: sectors per cluster (1, 2, 4, 8, 16, 32, 64)
    4 bytes: total number of clusters
    4 bytes: cluster table location (first cluster)
    4 bytes: number of files
    4 bytes: file table location

### Cluster Table
List of Cluter availibilities. 
This cluster has a cluster header.
The cluster table is a list of cluster table entries. the entries can overflow to
multiple cluster. Thus, to view the whole table, the cluster list must be
iterated through the cluster header 'next' field. The index of cluster table
entries is implicit by their location.

#### Cluster Table Entry
    4 bits: cluster bit vector

possible cluster flags:

* 0x1: cluster allocated
* 0x2: sustem cluster
* 0x4: ?
* 0x8: cluster has a bad sector

cluster table enties are packed 2 per byte.
There are ((sizeof(CLUSTER) - sizeof(ClusterHeader)) * 4) entries per cluster.

### File Table
A list of File Info entries
The first entry in the file table is the root directory

#### File Info Entry
    15 byte: filename
    1 byte: attributes
    4 byte: file size
    4 byte: start cluster 
    4 byte: creation time (unix time)
    4 byte: modification time (unix time)
    32

    attributes bit vector:
    (0 is least significant bit) 
    bit 0: directory
    bit 1: hidden
    bit 2: read only
    ...

    
### Directories
directories are represented as a list of 4 byte (int) indices into the FileTable. 
Directories are still files, and can be broken into multiple clusters. 
Each cluster of a directory has a Cluster Header. There is no sort order to directory entries.

A value of 0xffff as a fileId entry is an invalid file (file has been removed)
