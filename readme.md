#Make it executable.

bash
chmod +x oci-reset.sh

#Run it on any OCI instance using the raw GitHub URL:

bash

# Using curl

curl -O https://raw.githubusercontent.com/jaikhlang/cleaner/refs/heads/main/oci-reset.sh
chmod +x oci-reset.sh
sudo ./oci-reset.sh --force

sync && echo 3 > /proc/sys/vm/drop_caches

# One Line command

sudo bash -c "curl -s https://raw.githubusercontent.com/jaikhlang/cleaner/refs/heads/main/oci-reset.sh | bash -s -- --force && sync && echo 3 > /proc/sys/vm/drop_caches && free -h"
