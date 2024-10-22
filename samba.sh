#!/bin/bash
if  (( $EUID != 0 )); 
then
    echo "Vui lòng chạy script với quyền sudo. (lệnh: sudo bash samba.sh)"
    exit;
else
    echo "Script sẽ kiểm tra xem bạn đã cài đặt Samba hay chưa, và sẽ tự động chạy quy trình cài đặt nếu cần."
fi

rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY*
#yum install samba -y
systemctl stop firewalld
systemctl disable firewalld
useradd --system shareuser

init_domain() {
echo "Bắt đầu cấu hình Samba (đang chỉnh sửa smb.conf)"
cat <<EOL > /etc/samba/smb.conf
[Global]
 workgroup = $domainname
 realm = $domainname
 security = user
 domain master = yes
 domain logons = yes
 local master = yes
 preferred master = yes
 passdb backend = tdbsam
 idmap config * : range = 3000 - 7999
 idmap config * : backend = tdb
 logon path = \\\\%L\Profiles\%U
 logon script = logon.bat
 add machine script = /usr/sbin/useradd -d /dev/null -g 200 -s /sbin/nologin -M %u
 lanman auth = yes
 ntlm auth = yes

[homes]
 comment = Thư mục Home
 browseable = yes
 writable = yes

[netlogon]
 comment = Dịch vụ đăng nhập mạng
 path = /var/lib/samba/netlogon
 browseable = no
 writable = no

[Profiles]
 path = /var/lib/samba/profiles
 create mask = 0755
 directory mask = 0755
 writable = yes
EOL
}

FILE=/etc/samba/smb.conf.orig
if test -f "$FILE"; then
    echo "$FILE đã tồn tại. Do đó, sẽ không tạo tệp mới."
else
    echo "Không tìm thấy tệp sao lưu. Bắt đầu quy trình sao lưu... Vui lòng kiểm tra xem /etc/samba/smb.conf.orig có tồn tại không, nếu cần."
    sudo mv /etc/samba/smb.conf /etc/samba/smb.conf.orig
    touch /etc/samba/smb.conf
fi

# Menu chính
while true; do
    clear
    echo "Tùy chọn Menu:"
    echo "0. Kiểm tra cài đặt samba "
    echo "1. Khởi tạo chia sẻ tệp"
    echo "2. Tạo chia sẻ tệp mới"
    echo "3. Xóa một chia sẻ hiện có"
    echo "4. Liệt kê tất cả các chia sẻ"
    echo "5. Khởi tạo bộ điều khiển miền"
    echo "6. Thêm người dùng mới và thêm vào Samba"
    echo "7. Tạo tài khoản máy"
    echo "8. Thêm tài khoản vào Samba"
    echo "9. Kiểm tra cấu hình với testparm"
    echo "10. Đổi mật khẩu của người dùng Samba"
    echo "11. Hiển thị thông tin về tài khoản Samba"
    echo "12. Tải xuống từ chia sẻ tệp"
    echo "13. Vô hiệu hóa SELinux"
    echo "14. Thoát"
    echo "Nhập lựa chọn của bạn: "
    read choice

    case $choice in
        0)
        clear
        read -p "Bạn có chắc chắn muốn kiểm tra cài đặt Samba không? (yes/no): " confirm
        if [[ "$confirm" == "yes" ]]; then
            if command -v smbd &> /dev/null
            then
                version=$(smbd --version)
                echo "Samba đã được cài đặt. Phiên bản hiện tại: $version"
            else
                echo "Samba chưa được cài đặt."
                while true; do
                    read -p "Bạn có muốn cài đặt Samba không? (yes/no): " install_choice
                    if [[ "$install_choice" == "yes" ]]; then
                        # Tiến hành cài đặt Samba
                        echo "Đang cài đặt Samba..."
                        yum install samba -y
                        if [ $? -eq 0 ]; then
                            echo "Samba đã được cài đặt thành công!"
                        else
                            echo "Cài đặt Samba thất bại. Vui lòng thử lại."
                        fi
                        break
                    elif [[ "$install_choice" == "no" ]]; then
                        echo "Quay lại menu chính..."
                        break
                    else
                        echo "Lựa chọn không hợp lệ. Vui lòng nhập 'yes' hoặc 'no'."
                    fi
                done
            fi
        else
            echo "Hủy bỏ kiểm tra cài đặt Samba."
        fi
        ;;
        1)
        read -p "Bạn có chắc chắn muốn thêm [global] không? (yes/no): " confirm
        if [[ "$confirm" == "yes" ]]; then
            echo "Thêm [global]..."
            echo "[global]" > /etc/samba/smb.conf
            echo "	server role = standalone server" >> /etc/samba/smb.conf
            echo "	map to guest = bad user" >> /etc/samba/smb.conf
            echo "	usershare allow guests = yes" >> /etc/samba/smb.conf
            systemctl restart smb
            systemctl restart nmb
            echo "Thêm [global] thành công!"
        else
            echo "Hủy bỏ thêm [global]."
        fi
        ;;
        2)
        clear
        read -p "Bạn có chắc chắn muốn tạo chia sẻ tệp mới không? (yes/no): " confirm
        if [[ "$confirm" == "yes" ]]; then
            echo "Bạn muốn đặt tên cho kết nối chia sẻ này là gì? (lưu ý: không phải thư mục)"
            read sharename
            echo "Tên kết nối đã nhập: $sharename."

            echo "Đường dẫn của thư mục là gì?"
            read pathname
            if [ -d "$pathname" ]; then
                echo "Thư mục ${pathname} đã được tìm thấy, tiếp tục..."
            else
                echo "Không tìm thấy thư mục, một thư mục mới sẽ được tạo"
                mkdir $pathname
            fi
            echo "Đường dẫn thư mục đã nhập: $pathname."

            echo "Bình luận cho kết nối chia sẻ này?"
            read comment
            echo "Bình luận đã nhập: $comment."

            while true; 
            do
                read -p "Có thể ghi? Vui lòng nhập 'yes' hoặc 'no': " writable
                if [[ "$writable" == "yes" || "$writable" == "no" ]]; then
                    break
                else
                    echo "Đầu vào không hợp lệ. Vui lòng thử lại."
                fi
            done

            echo "Đầu vào đã nhập (có thể ghi): $writable."

            echo "[${sharename}]" >> /etc/samba/smb.conf
            echo "	path = ${pathname}" >> /etc/samba/smb.conf
            echo "	comment = ${comment}" >> /etc/samba/smb.conf
            echo "	guest ok = yes" >> /etc/samba/smb.conf
            echo "	writable = ${writable}" >> /etc/samba/smb.conf
            echo "	force user = shareuser" >> /etc/samba/smb.conf
            chmod -R 775 $pathname
            chown -R shareuser $pathname

            systemctl restart smb
            systemctl restart nmb
            echo "Chia sẻ tệp mới đã được tạo thành công!"
        else
            echo "Hủy bỏ tạo chia sẻ tệp mới."
        fi
        ;;
        3)
        clear
        read -p "Bạn có chắc chắn muốn xóa kết nối không? (yes/no): " confirm
        if [[ "$confirm" == "yes" ]]; then
            echo "Bạn muốn xóa kết nối nào?"
            while true; 
            do
                read connection
                linenumber=$(grep -xn "\[${connection}\]" /etc/samba/smb.conf | awk -F: '{print$1}')
                if [[ "$linenumber" -eq 1 ]]; then
                    echo "Bạn không được phép xóa [global]. Vui lòng nhập lại."
                else
                    break
                fi
            done

            if [ -z $linenumber ] ; then
                echo "Không tìm thấy kết nối nào. Thoát script."
                exit
            fi
            echo "Dòng đang xử lý: ${linenumber}."
            finalnumber=$(( $linenumber+5 ))
            echo "Các dòng sẽ xóa: từ ${linenumber} đến ${finalnumber}."

            sed -i "${linenumber},${finalnumber}d" /etc/samba/smb.conf

            systemctl restart smb
            systemctl restart nmb
            echo "Kết nối đã được xóa thành công!"
        else
            echo "Hủy bỏ xóa kết nối."
        fi
        ;;
        4)
        clear
        read -p "Bạn có chắc chắn muốn liệt kê tất cả các chia sẻ không? (yes/no): " confirm
        if [[ "$confirm" == "yes" ]]; then
            config_file="/etc/samba/smb.conf"

            share_names=$(grep -E "^\[.*\]$" "$config_file" | sed 's/\[//' | sed 's/\]//')
            echo "Danh sách các chia sẻ hiện có trong Samba."

            for share_name in $share_names; 
            do
                echo "$share_name"
            done
        else
            echo "Hủy bỏ liệt kê chia sẻ."
        fi
        ;;
        5)
        clear
        read -p "Bạn có chắc chắn muốn khởi tạo bộ điều khiển miền không? (yes/no): " confirm
        if [[ "$confirm" == "yes" ]]; then
            read -p "Vui lòng nhập tên bạn muốn đặt cho miền của bạn: " domainname

            init_domain
            mkdir -m 1777 /var/lib/samba/netlogon
            mkdir -m 1777 /var/lib/samba/profiles
            groupadd -g 200 machine

            systemctl restart smb
            systemctl restart nmb
            echo "Khởi tạo bộ điều khiển miền thành công!"
        else
            echo "Hủy bỏ khởi tạo bộ điều khiển miền."
        fi
        ;;
        6)
        clear
        read -p "Bạn có chắc chắn muốn thêm người dùng mới không? (yes/no): " confirm
        if [[ "$confirm" == "yes" ]]; then
            while true; do
                read -p "Nhập số lượng người dùng bạn muốn tạo (tối đa là 3): " num_users

                if ((num_users > 3)); then
                    echo "Chỉ cho phép tạo tối đa 3 người dùng."
                else
                    break
                fi
            done

            for ((i=1; i<=num_users; i++)); do
                read -p "Nhập tên người dùng cho người dùng # $i: " username
                if id "$username" &>/dev/null; then
                    echo "Người dùng $username đã tồn tại..."
                else
                    echo "Tạo người dùng $username..."
                    useradd "$username"
                    smbpasswd -a "$username"
                    echo "Người dùng $username đã được tạo."
                fi
            done    

            systemctl restart smb
            systemctl restart nmb    
            echo "Thêm người dùng mới thành công!"
        else
            echo "Hủy bỏ thêm người dùng mới."
        fi
        ;;
        7)
        clear
        read -p "Bạn có chắc chắn muốn tạo tài khoản máy không? (yes/no): " confirm
        if [[ "$confirm" == "yes" ]]; then
            read -p "Nhập tên cho tài khoản máy (ví dụ: machine1): " machine_name
            machine_account="${machine_name}\$"

            if id "$machine_account" &>/dev/null; then
                echo "Tài khoản máy $machine_account đã tồn tại..."
            else
                echo "Tạo tài khoản máy $machine_account..."
                groupadd -g 200 machine
                smbpasswd -m -a "$machine_account"
                echo "Tài khoản máy $machine_account đã được tạo."
            fi

            systemctl restart smb
            systemctl restart nmb
            echo "Tạo tài khoản máy thành công!"
        else
            echo "Hủy bỏ tạo tài khoản máy."
        fi
        ;;
        8)
        clear
        read -p "Bạn có chắc chắn muốn thêm tài khoản vào Samba không? (yes/no): " confirm
        if [[ "$confirm" == "yes" ]]; then
            read -p "Nhập tài khoản bạn muốn thêm vào Samba: " samba_username
            sudo smbpasswd -a "$samba_username"
            if [ $? -eq 0 ]; then
                echo "Tài khoản $samba_username đã được thêm vào Samba."
            else
                echo "Thêm $samba_username vào Samba không thành công. Vui lòng thử lại."
            fi    

            systemctl restart smb
            systemctl restart nmb    
        else
            echo "Hủy bỏ thêm tài khoản vào Samba."
        fi
        ;;
        9)
        clear
        read -p "Bạn có chắc chắn muốn kiểm tra cấu hình với testparm không? (yes/no): " confirm
        if [[ "$confirm" == "yes" ]]; then
            if [ ! -f /etc/samba/smb.conf ]; then
                echo "Không tìm thấy smb.conf"
                exit 1 
            fi

            output=$(testparm -s)

            if [ $? -eq 0 ]; then
                echo "smb.conf được cấu hình đúng."
                echo "$output"
            else
                echo "smb.conf được cấu hình sai..."
                echo "Chi tiết lỗi: "
                echo "$output"
            fi
        else
            echo "Hủy bỏ kiểm tra cấu hình."
        fi
        ;;
        10)
        clear
        read -p "Bạn có chắc chắn muốn đổi mật khẩu Samba không? (yes/no): " confirm
        if [[ "$confirm" == "yes" ]]; then
            read -p "Nhập tên người dùng: " username

            smbpasswd $username

            systemctl restart smb
            systemctl restart nmb
            echo "Đổi mật khẩu thành công!"
        else
            echo "Hủy bỏ đổi mật khẩu."
        fi
        ;;
        11)
        clear
        read -p "Bạn có chắc chắn muốn hiển thị thông tin về tài khoản Samba không? (yes/no): " confirm
        if [[ "$confirm" == "yes" ]]; then
            echo "Danh sách người dùng Samba:"
            pdbedit -L

            read -p "Vui lòng nhập tên người dùng bạn muốn xem thông tin (để trống để xem tất cả người dùng): " user_to_show
            echo "Thông tin của $user_to_show:"
            pdbedit -L -v $user_to_show
        else
            echo "Hủy bỏ hiển thị thông tin."
        fi
        ;;
        12)
        clear
        read -p "Bạn có chắc chắn muốn tải xuống từ chia sẻ tệp không? (yes/no): " confirm
        if [[ "$confirm" == "yes" ]]; then
            echo "Đang cố tải xuống từ chia sẻ tệp..."
            echo "Địa chỉ IP của máy chủ Samba: "
            read sambaserver
            echo "Tên của chia sẻ tệp bạn muốn tải xuống: "
            read fileshare
            smbget -R smb://$sambaserver/$fileshare
            echo "Tải xuống thành công!"
        else
            echo "Hủy bỏ tải xuống."
        fi
        ;;
        13)
        clear
        read -p "Bạn có chắc chắn muốn vô hiệu hóa SELinux không? (yes/no): " confirm
        if [[ "$confirm" == "yes" ]]; then
            echo "Đang cố gắng vô hiệu hóa SELinux..."

            setenforce 0

            sed -i 's/^SELINUX=.*/SELINUX=disabled/' /etc/selinux/config

            echo "Tệp cấu hình SELinux đã thay đổi. Vui lòng KHỞI ĐỘNG LẠI máy tính để áp dụng thay đổi..."
        else
            echo "Hủy bỏ vô hiệu hóa SELinux."
        fi
        ;;
        14)
        read -p "Bạn có chắc chắn muốn thoát không? (yes/no): " confirm
        if [[ "$confirm" == "yes" ]]; then
            echo "Thoát khỏi chương trình..."
            exit
        else
            echo "Hủy bỏ thoát chương trình."
        fi
        ;;
        *)
            echo "Lựa chọn không hợp lệ. Vui lòng chọn tùy chọn hợp lệ."
            ;;
esac

systemctl restart smb
systemctl restart nmb
echo "Nhấn Enter để tiếp tục..."
read
done
