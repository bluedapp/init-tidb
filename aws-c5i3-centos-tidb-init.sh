#!/bin/bash

echo "Ready to initialize disks"

UserFsType='ext4'
UserMount='/data'

echo "Check out all active disks:"
fdisk -l 2>&1 | grep -o "Disk /dev/nvme[0-9]n1" | egrep -v "xvda|nvme0n1p1"


check_new_or_not() {
	echo "Check whether this instance is new or not"
	for Disk in `fdisk -l 2>&1 | grep -o "Disk /dev/nvme[0-9]n1" | egrep -v "xvda|nvme0n1" | awk '{print $2}'`; 
	do
		lines=`hexdump -C -n 1048576 $Disk | wc -l`
		echo "Counting $lines lines from $Disk"
		if [ $lines -gt 3 ]; then
			echo "Not a new instance, stop initializing disks"	
			exit
		fi
		
		echo "$col" | cut -d ':' -f 2
	done
	
	echo "New instance"
}

init_disk() {
	DiskNum=0
	for Disk in `fdisk -l 2>&1 | egrep -o "Disk /dev/nvme[0-9]n1|Disk /dev/xvda" | awk '{print $2}'`;
	do
		DiskNum=`expr $DiskNum + 1`
	done 
	echo "Detect $DiskNum datadisks"
	if [ $DiskNum -gt 2 ]
	then
		init_multiple_disk
	else
		Disk=`fdisk -l 2>&1 | grep -o "Disk /dev/nvme[0-9]n1" | egrep -v "xvda|nvme0n1" | awk '{print $2}'`
		init_single_disk $UserMount $Disk $UserFsType 
	fi
}


init_multiple_disk() {
	yum install -y mdadm
	DiskCounts=$(fdisk -l 2>&1 | grep -o "Disk /dev/nvme[0-9]n1" | egrep -v "xvda" |wc -l)
	if [ $DiskCounts -eq 2 ]
	then
		mdadm --create /dev/md0 --level=0 --raid-devices=$DiskCounts /dev/nvme[0-$DiskCounts]n1
		mkfs -t ext4  /dev/md0
		mdadm -Ds >> /etc/mdadm.conf 
		echo "$(blkid |grep md|awk '{print $2}')  /data   ext4 defaults,nodelalloc,noatime     0   2" >> /etc/fstab
		mount -a
		echo "Finish initializing $DiskCounts disks for raid0"
	fi
}

init_single_disk() {
	MountDir=$1
	Disk=$2
	FsType=$3
	echo 'Initializing '$Disk''
	mkfs -t $FsType $Disk  2>&1
	mkdir -p $MountDir 2>&1
	mount $Disk $MountDir
	chown centos:centos $MountDir
	chmod 757 $MountDir
	temp=`echo $Disk | sed 's;/;\\\/;g'`
	sed -i -e "/^$temp/d" /etc/fstab
	echo $Disk $MountDir $FsType 'defaults,nodelalloc,noatime 0 0' >> /etc/fstab
	echo 'Finish initializing '$Disk', mounted on '$MountDir''
}

init_centos_users() {
	echo "centos:$YOUR-SYSTEM-PASSWORD"| chpasswd
}

init_tidb_users() {
	useradd -m -r -s /bin/bash tidb
	echo "tidb:$YOUR-TIUP-PASSWORD"| chpasswd
	mkdir /home/tidb/.ssh
	echo "ssh-rsa $YOUR-LOGIN-RSA" |  tee -a /home/tidb/.ssh/authorized_keys
	chmod 600 /home/tidb/.ssh/authorized_keys
	chown -R tidb:tidb /home/tidb
	chmod 700 /home/tidb/.ssh
	echo "tidb ALL=(ALL) NOPASSWD:ALL" |  tee -a /etc/sudoers.d/tidb
	chown  root:root /etc/sudoers.d/tidb
	chmod 400 /etc/sudoers.d/tidb
}


init_system() {
	#cloud swap
	echo "vm.swappiness = 0"|tee -a /etc/sysctl.conf
	/sbin/swapoff -a && /sbin/swapon -a
	sysctl -p
	#set timezone
	timedatectl set-timezone Asia/Singapore
	if [ $? -ne 0  ]
	then
		yum install -y ntp ntpdate && systemctl start ntpd.service && systemctl enable ntpd.service
	fi
	#set tuned
	DATA_DEV=$(df |grep data|awk '{print $1}')
	ID_SERIAL=$(blkid|grep $DATA_DEV|awk -F '"' '{print $2}')
	mkdir /etc/tuned/balanced-tidb-optimal
	tee -a /etc/tuned/balanced-tidb-optimal/tuned.conf << EOF
[main]
include=balanced

[cpu]
governor=performance

[vm]
transparent_hugepages=never

[disk]
devices_udev_regex=(ID_SERIAL=$ID_SERIAL)
elevator=noop
EOF
	tuned-adm profile balanced-tidb-optimal
	#close thp
	echo "echo 'never' | sudo tee /sys/kernel/mm/transparent_hugepage/defrag"|tee -a /etc/rc.local
	echo "echo 'never' | sudo tee /sys/kernel/mm/transparent_hugepage/enabled"|tee -a /etc/rc.local
	#set system.conf
	tee -a /etc/sysctl.conf << EOF
fs.file-max = 1000000
net.core.somaxconn = 32768
net.ipv4.tcp_tw_recycle = 0
net.ipv4.tcp_syncookies = 0
vm.overcommit_memory = 1
vm.swappiness = 0
EOF
	sysctl -p
	#set limits.conf
	tee -a /etc/security/limits.conf << EOF
tidb           soft    nofile          1000000
tidb           hard    nofile          1000000
tidb           soft    stack          32768
tidb           hard    stack          32768
EOF
	#install some service
	yum -y install numactl irqbalance
	systemctl enable irqbalance
	irqbalance_temp=$(cat /etc/rc.local|grep irqbalance)
	sed -i -e "/^$irqbalance_temp/d" /etc/rc.local
	echo "sudo systemctl start irqbalance"|tee -a /etc/rc.local
}


#check_new_or_not

init_disk

init_centos_users

init_tidb_users

init_system





