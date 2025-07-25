#!/bin/bash

# Script áp dụng tối ưu hóa cho Boundless Broker
# Chỉ sửa code, KHÔNG động vào broker.toml

set -e

echo "🚀 Áp dụng tối ưu hóa Boundless Broker..."

# Kiểm tra xem có trong thư mục đúng không
if [ ! -d "crates/broker/src" ]; then
    echo "❌ Lỗi: Không tìm thấy thư mục crates/broker/src"
    echo "   Hãy chạy script này từ thư mục gốc của Boundless project"
    exit 1
fi

# Backup files trước khi sửa
echo "📝 Backup files gốc..."
BACKUP_DIR="backup_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

cp crates/broker/src/order_picker.rs "$BACKUP_DIR/"
cp crates/broker/src/prioritization.rs "$BACKUP_DIR/"

echo "✅ Backup saved to: $BACKUP_DIR"

# Áp dụng patch cho order_picker.rs
echo "🔨 Applying optimization to order_picker.rs..."
if patch -p1 < patch_order_picker.patch; then
    echo "✅ order_picker.rs optimized successfully!"
else
    echo "⚠️  Warning: Patch for order_picker.rs may have failed"
    echo "   Check the file manually or restore from backup"
fi

# Áp dụng patch cho prioritization.rs  
echo "🔨 Applying optimization to prioritization.rs..."
if patch -p1 < patch_prioritization.patch; then
    echo "✅ prioritization.rs optimized successfully!"
else
    echo "⚠️  Warning: Patch for prioritization.rs may have failed"
    echo "   Check the file manually or restore from backup"
fi

# Kiểm tra syntax
echo "🔍 Checking Rust syntax..."
if cargo check --bin broker 2>/dev/null; then
    echo "✅ Syntax check passed!"
else
    echo "❌ Syntax errors found. Restoring backup..."
    cp "$BACKUP_DIR/order_picker.rs" crates/broker/src/
    cp "$BACKUP_DIR/prioritization.rs" crates/broker/src/
    echo "🔄 Files restored from backup"
    exit 1
fi

# Build để đảm bảo code compile được
echo "🏗️  Building broker..."
if cargo build --bin broker --release; then
    echo "✅ Build successful!"
else
    echo "❌ Build failed. Restoring backup..."
    cp "$BACKUP_DIR/order_picker.rs" crates/broker/src/
    cp "$BACKUP_DIR/prioritization.rs" crates/broker/src/
    echo "🔄 Files restored from backup"
    exit 1
fi

echo ""
echo "🎉 Tối ưu hóa hoàn tất!"
echo "======================"
echo ""
echo "📋 Các thay đổi đã áp dụng:"
echo ""
echo "🔧 order_picker.rs:"
echo "  • Aggressive pricing (chấp nhận giá thấp hơn 20%)"
echo "  • Early bidding (bid ở 25% ramp time thay vì 50%)"
echo "  • High-value order priority (bid ở 12.5% cho order lớn)"
echo ""
echo "🔧 prioritization.rs:"
echo "  • Value-based sorting (ưu tiên order có giá trị cao)"
echo "  • Weighted random (giữ 50% top orders)"
echo "  • Enhanced expiry sorting (kết hợp expiry + price)"
echo ""
echo "📁 Backup location: $BACKUP_DIR"
echo ""
echo "🚀 Để khởi động broker với tối ưu hóa:"
echo "   cargo run --release --bin broker"
echo ""
echo "📊 Để monitor hiệu quả:"
echo "   tail -f broker.log | grep -E '(locked|fulfilled|Selecting order)'"
echo ""
echo "🔄 Để restore backup nếu cần:"
echo "   cp $BACKUP_DIR/* crates/broker/src/"
echo ""
echo "💡 Lưu ý:"
echo "  • Các tối ưu hóa này sẽ giúp broker cạnh tranh tích cực hơn"
echo "  • Monitor logs để đảm bảo hoạt động ổn định"
echo "  • Điều chỉnh thêm dựa trên kết quả thực tế"
echo ""
echo "🏆 Chúc bạn nhận được nhiều order hơn!"