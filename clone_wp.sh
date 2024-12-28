#!/bin/bash

# Đường dẫn và thông tin cần thiết
OLD_SERVER_IP=""
OLD_SITE_PATH=""
NEW_DOMAIN=""
NEW_SITE_PATH="/var/www"
SSH_USER="root"
WP_DB_DUMP="wp-database.sql"

# Hàm hiển thị thông báo lỗi và thoát
error_exit() {
    echo "Lỗi: $1"
    exit 1
}

# Nhập IP máy chủ cũ
read -p "Nhập IP máy chủ cũ: " OLD_SERVER_IP
if [[ -z "$OLD_SERVER_IP" ]]; then
    error_exit "IP máy chủ cũ không được để trống!"
fi

# Nhập tên miền mới
read -p "Nhập tên miền mới: " NEW_DOMAIN
if [[ -z "$NEW_DOMAIN" ]]; then
    error_exit "Tên miền không được để trống!"
fi

# Nhập đường dẫn thư mục của máy chủ cũ
read -p "Nhập đường dẫn thư mục trên máy chủ cũ (ví dụ: /var/www/example.com/htdocs): " OLD_SITE_PATH
if [[ -z "$OLD_SITE_PATH" ]]; then
    error_exit "Đường dẫn thư mục không được để trống!"
fi

# Kiểm tra WordOps đã cài đặt chưa
if ! command -v wo &> /dev/null; then
    echo "WordOps chưa được cài đặt. Đang tiến hành cài đặt..."
    wget -qO wo wops.cc && sudo bash wo || error_exit "Cài đặt WordOps thất bại"
else
    echo "WordOps đã được cài đặt. Bỏ qua bước cài đặt."
fi

# Kiểm tra tên miền đã tồn tại chưa
if [[ -d "$NEW_SITE_PATH/$NEW_DOMAIN" ]]; then
    echo "Tên miền $NEW_DOMAIN đã tồn tại. Đang dọn dẹp dữ liệu cũ..."
    sudo -u www-data -H wp db clean --yes --path="$NEW_SITE_PATH/$NEW_DOMAIN/htdocs" || error_exit "Dọn dẹp cơ sở dữ liệu thất bại"
    rm -rf "$NEW_SITE_PATH/$NEW_DOMAIN/htdocs/*" || error_exit "Xóa tệp mặc định thất bại"
else
    echo "Tên miền $NEW_DOMAIN chưa tồn tại. Đang tạo mới..."
    sudo wo site create "$NEW_DOMAIN" --wpredis || error_exit "Tạo trang WordPress thất bại"
fi

# Thiết lập SSH không cần mật khẩu
echo "Thiết lập truy cập SSH không cần mật khẩu..."
if [[ ! -f ~/.ssh/id_rsa.pub ]]; then
    ssh-keygen -t rsa -N "" -f ~/.ssh/id_rsa || error_exit "Tạo SSH Key thất bại"
fi
ssh-copy-id "$SSH_USER@$OLD_SERVER_IP" || error_exit "Thêm SSH Key vào máy chủ cũ thất bại"

# Sao chép dữ liệu từ máy chủ cũ
echo "Sao chép dữ liệu từ máy chủ cũ..."
rsync -avzh --progress --ignore-existing "$SSH_USER@$OLD_SERVER_IP:$OLD_SITE_PATH/" "$NEW_SITE_PATH/$NEW_DOMAIN/htdocs/" || error_exit "Sao chép dữ liệu thất bại"

# Loại bỏ wp-config.php nếu tồn tại
echo "Loại bỏ tệp wp-config.php cũ nếu có..."
if [[ -f "$NEW_SITE_PATH/$NEW_DOMAIN/htdocs/wp-config.php" ]]; then
    mv "$NEW_SITE_PATH/$NEW_DOMAIN/htdocs/wp-config.php" "$NEW_SITE_PATH/$NEW_DOMAIN/wp-config.php.bak" || error_exit "Không thể di chuyển wp-config.php"
fi

# Khôi phục cơ sở dữ liệu
echo "Khôi phục cơ sở dữ liệu..."
scp "$SSH_USER@$OLD_SERVER_IP:$OLD_SITE_PATH/$WP_DB_DUMP" "$NEW_SITE_PATH/$NEW_DOMAIN/htdocs/" || error_exit "Không thể sao chép cơ sở dữ liệu"
cd "$NEW_SITE_PATH/$NEW_DOMAIN/htdocs" || error_exit "Không thể truy cập vào thư mục htdocs"
wp db import "$WP_DB_DUMP" --allow-root || error_exit "Khôi phục cơ sở dữ liệu thất bại"
rm "$WP_DB_DUMP" || error_exit "Không thể xóa tệp cơ sở dữ liệu sau khi nhập"

# Cấp chứng chỉ SSL
echo "Cấp chứng chỉ SSL cho tên miền $NEW_DOMAIN..."
wo site update "$NEW_DOMAIN" -le || error_exit "Cấp chứng chỉ SSL thất bại"

# Hoàn tất
echo "Quá trình di chuyển WordPress cho tên miền $NEW_DOMAIN đã hoàn tất!"
