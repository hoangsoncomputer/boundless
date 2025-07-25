#!/bin/bash

# Script tối ưu hóa Boundless Broker để cạnh tranh hiệu quả hơn
# Tác giả: AI Assistant
# Mục đích: Giúp broker nhận được nhiều order hơn

set -e

echo "🚀 Bắt đầu tối ưu hóa Boundless Broker..."

# Kiểm tra xem có file broker.toml không
if [ ! -f "broker.toml" ]; then
    echo "⚠️  Không tìm thấy broker.toml, tạo từ template..."
    cp broker-optimized.toml broker.toml
else
    echo "📝 Backup broker.toml hiện tại..."
    cp broker.toml broker.toml.backup.$(date +%Y%m%d_%H%M%S)
fi

# Áp dụng cấu hình tối ưu
echo "⚙️  Áp dụng cấu hình tối ưu..."
cp broker-optimized.toml broker.toml

# Tạo thư mục cache nếu chưa có
echo "📁 Tạo thư mục cache..."
mkdir -p /tmp/broker_cache
chmod 755 /tmp/broker_cache

# Kiểm tra và tối ưu hóa system limits
echo "🔧 Tối ưu hóa system limits..."

# Tăng file descriptor limits
if [ -f /etc/security/limits.conf ]; then
    echo "* soft nofile 65536" | sudo tee -a /etc/security/limits.conf
    echo "* hard nofile 65536" | sudo tee -a /etc/security/limits.conf
fi

# Tối ưu hóa network settings
if [ -f /etc/sysctl.conf ]; then
    echo "# Boundless Broker optimizations" | sudo tee -a /etc/sysctl.conf
    echo "net.core.somaxconn = 4096" | sudo tee -a /etc/sysctl.conf
    echo "net.core.netdev_max_backlog = 5000" | sudo tee -a /etc/sysctl.conf
    echo "net.ipv4.tcp_max_syn_backlog = 4096" | sudo tee -a /etc/sysctl.conf
    echo "net.ipv4.tcp_keepalive_time = 600" | sudo tee -a /etc/sysctl.conf
    sudo sysctl -p
fi

# Áp dụng patch code nếu có
if [ -f "order_picker_optimized.patch" ]; then
    echo "🔨 Áp dụng patch code tối ưu hóa..."
    
    # Backup code gốc
    if [ -f "crates/broker/src/order_picker.rs" ]; then
        cp crates/broker/src/order_picker.rs crates/broker/src/order_picker.rs.backup.$(date +%Y%m%d_%H%M%S)
    fi
    
    # Thử áp dụng patch
    if patch -p1 < order_picker_optimized.patch; then
        echo "✅ Patch áp dụng thành công!"
    else
        echo "⚠️  Patch không áp dụng được, có thể code đã được sửa đổi"
    fi
fi

# Tạo script monitoring
echo "📊 Tạo script monitoring..."
cat > monitor_broker.sh << 'EOF'
#!/bin/bash

# Script monitoring broker performance
echo "🔍 Boundless Broker Monitor"
echo "=========================="

# Kiểm tra số lượng order đang xử lý
echo "📈 Orders trong database:"
if [ -f broker.db ]; then
    sqlite3 broker.db "SELECT status, COUNT(*) FROM orders GROUP BY status;" 2>/dev/null || echo "Không thể truy cập database"
fi

# Kiểm tra memory usage
echo ""
echo "💾 Memory Usage:"
ps aux | grep broker | grep -v grep | awk '{print $4"% - "$11}' || echo "Broker không chạy"

# Kiểm tra network connections
echo ""
echo "🌐 Network Connections:"
netstat -an | grep :8545 | wc -l | awk '{print "RPC connections: "$1}'

# Kiểm tra disk space
echo ""
echo "💿 Disk Space:"
df -h /tmp/broker_cache 2>/dev/null || echo "Cache directory không tồn tại"

# Kiểm tra log errors gần đây
echo ""
echo "🚨 Recent Errors (last 10):"
if [ -f broker.log ]; then
    tail -1000 broker.log | grep -i error | tail -10 || echo "Không có lỗi gần đây"
else
    echo "Không tìm thấy log file"
fi

echo ""
echo "✅ Monitor completed"
EOF

chmod +x monitor_broker.sh

# Tạo script khởi động tối ưu
echo "🚀 Tạo script khởi động tối ưu..."
cat > start_optimized_broker.sh << 'EOF'
#!/bin/bash

# Script khởi động broker với các tối ưu hóa
echo "🚀 Khởi động Optimized Boundless Broker..."

# Set environment variables for optimization
export RUST_LOG="info,boundless_market=debug,broker=debug"
export RUST_BACKTRACE=1

# JVM-like memory settings for Rust
export RUSTFLAGS="-C target-cpu=native -C opt-level=3"

# Increase stack size
ulimit -s 16384

# Set nice priority for better scheduling
nice -n -10 cargo run --release --bin broker -- \
    --config broker.toml \
    2>&1 | tee -a broker.log
EOF

chmod +x start_optimized_broker.sh

# Tạo script benchmark
echo "⚡ Tạo script benchmark..."
cat > benchmark_broker.sh << 'EOF'
#!/bin/bash

# Script benchmark hiệu suất broker
echo "⚡ Benchmark Boundless Broker"
echo "============================"

# Test RPC response time
echo "🌐 Testing RPC response time..."
if command -v curl &> /dev/null; then
    for i in {1..5}; do
        start_time=$(date +%s%N)
        curl -s -X POST -H "Content-Type: application/json" \
             --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
             $RPC_URL > /dev/null
        end_time=$(date +%s%N)
        duration=$(( (end_time - start_time) / 1000000 ))
        echo "Request $i: ${duration}ms"
    done
fi

# Test proving speed (if bento is available)
echo ""
echo "⚡ Testing proving speed..."
if command -v bento &> /dev/null; then
    echo "Bento benchmark sẽ được chạy..."
    # Thêm benchmark code ở đây
else
    echo "Bento không có sẵn để benchmark"
fi

echo ""
echo "✅ Benchmark completed"
EOF

chmod +x benchmark_broker.sh

# In hướng dẫn sử dụng
echo ""
echo "🎉 Tối ưu hóa hoàn tất!"
echo "======================"
echo ""
echo "📋 Các file đã được tạo:"
echo "  • broker.toml - Cấu hình tối ưu"
echo "  • start_optimized_broker.sh - Script khởi động"
echo "  • monitor_broker.sh - Script monitoring"
echo "  • benchmark_broker.sh - Script benchmark"
echo ""
echo "🚀 Để khởi động broker tối ưu:"
echo "  ./start_optimized_broker.sh"
echo ""
echo "📊 Để monitor hiệu suất:"
echo "  ./monitor_broker.sh"
echo ""
echo "⚡ Để benchmark:"
echo "  ./benchmark_broker.sh"
echo ""
echo "⚠️  Lưu ý quan trọng:"
echo "  1. Đảm bảo có đủ USDC stake (ít nhất 100 USDC)"
echo "  2. Kiểm tra RPC_URL và PRIVATE_KEY"
echo "  3. Monitor logs để điều chỉnh thêm"
echo "  4. Backup được tạo với timestamp"
echo ""
echo "💡 Các tối ưu hóa chính:"
echo "  • Giá mcycle_price thấp hơn (0.0000001)"
echo "  • Bid sớm hơn (25% thời gian ramp)"
echo "  • Xử lý concurrent cao hơn (10 proofs, 20 preflights)"
echo "  • Priority gas cao hơn (500)"
echo "  • Cache để tăng tốc"
echo "  • System limits được tối ưu"
echo ""
echo "🏆 Chúc bạn nhận được nhiều order!"