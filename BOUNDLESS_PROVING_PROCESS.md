# 🔄 Quy Trình Prove Hoàn Chỉnh trong Boundless

## 📋 Tổng Quan Quy Trình

```
Client → Request → Market → Prover → Lock → Prove → Aggregate → Submit → Verify → Payment
```

## 🎯 Chi Tiết Từng Bước

### **1. 📝 Client Tạo Proof Request**

```rust
// Client tạo ProofRequest
let request = ProofRequest {
    id: request_id,
    requirements: Requirements {
        imageId: program_hash,
        predicate: conditions,
        selector: proof_type, // Groth16 hoặc Merkle
        callback: callback_contract,
    },
    imageUrl: "https://storage.com/program.bin",
    input: Input::Raw(input_data),
    offer: Offer {
        minPrice: 0.001 ETH,
        maxPrice: 0.005 ETH,
        biddingStart: now,
        rampDurationSecs: 600, // 10 phút
        lockTimeout: 1800,     // 30 phút
        timeout: 3600,         // 1 giờ
        lockStake: 5 USDC,
    },
};

// Submit lên market contract
market.submitRequest(request, signature);
```

### **2. 🔍 Prover Discovery & Evaluation**

#### **A. Order Discovery**
```rust
// Broker monitor blockchain events
market_monitor.on_new_request(|request| {
    // Tạo OrderRequest từ ProofRequest
    let order = OrderRequest::from_proof_request(request);
    order_picker.evaluate_order(order);
});
```

#### **B. Preflight Evaluation**
```rust
// Download và test program
let image_id = storage.download_image(request.imageUrl);
let input_id = storage.upload_input(request.input);

// Chạy preflight để tính cycles
let preflight_result = prover.preflight(image_id, input_id, exec_limit);
let total_cycles = preflight_result.stats.total_cycles;

// Tính toán chi phí và lợi nhuận
let cost = total_cycles * mcycle_price;
let profit = request.offer.maxPrice - cost - gas_cost;
```

### **3. 💰 Bidding & Pricing Decision**

#### **A. Price Analysis**
```rust
// Tính giá per megacycle
let mcycle_price_min = (offer.minPrice - gas_cost) * 1M / total_cycles;
let mcycle_price_max = (offer.maxPrice - gas_cost) * 1M / total_cycles;

// So sánh với config minimum
if mcycle_price_min < config.mcycle_price {
    return Skip; // Không đáng làm
}
```

#### **B. Timing Strategy**
```rust
// Tính thời điểm bid tối ưu
let bidding_start = offer.biddingStart;
let ramp_duration = offer.rampDurationSecs;

// Standard: bid ở 50% ramp time
let standard_time = bidding_start + (ramp_duration / 2);

// Optimized: bid ở 25% ramp time
let optimal_time = bidding_start + (ramp_duration / 4);

// High-value: bid ở 12.5% ramp time
let early_time = bidding_start + (ramp_duration / 8);

let target_time = if is_high_value_order {
    early_time
} else {
    optimal_time
};
```

### **4. 🔒 Lock Process**

#### **A. Wait for Target Time**
```rust
// Chờ đến thời điểm bid
tokio::time::sleep_until(target_timestamp).await;

// Kiểm tra order còn available không
if !market.is_order_available(request_id) {
    return AlreadyLocked;
}
```

#### **B. Execute Lock Transaction**
```rust
// Tính giá tại thời điểm hiện tại
let current_price = offer.price_at(now());

// Gửi lock transaction với priority gas
let tx = market.lockRequest(
    request_id,
    current_price,
    stake_amount
).with_gas_price(base_gas + priority_gas);

let receipt = tx.send().await?;
let lock_timestamp = get_block_timestamp(receipt.block_number);
```

### **5. ⚡ Proof Generation**

#### **A. Start STARK Proving**
```rust
// Bắt đầu prove STARK
let stark_session = prover.prove_stark(image_id, input_id).await?;
let stark_proof_id = stark_session.id;

// Monitor proving progress
loop {
    let status = prover.get_stark_status(stark_proof_id).await?;
    match status {
        ProvingStatus::Running => continue,
        ProvingStatus::Complete(proof) => break proof,
        ProvingStatus::Failed(err) => return Err(err),
    }
    tokio::time::sleep(Duration::from_secs(10)).await;
}
```

#### **B. SNARK Compression (nếu cần)**
```rust
if request.requirements.selector == Groth16 {
    // Compress STARK thành SNARK
    let snark_session = prover.compress_to_snark(stark_proof_id).await?;
    let snark_proof_id = snark_session.id;
    
    // Wait for compression
    let snark_proof = prover.wait_for_snark(snark_proof_id).await?;
}
```

### **6. 📦 Aggregation Process**

#### **A. Batch Collection**
```rust
// Collect multiple completed proofs
let completed_orders = db.get_completed_orders().await?;
let batch_size = min(completed_orders.len(), MAX_BATCH_SIZE);

// Create batch
let batch = Batch {
    id: generate_batch_id(),
    orders: completed_orders[..batch_size].to_vec(),
    status: BatchStatus::Aggregating,
    created_at: now(),
};
```

#### **B. Set Builder Proving**
```rust
// Tạo aggregation proof
let set_builder_input = create_set_builder_input(&batch.orders);
let aggregation_proof = prover.prove_set_builder(set_builder_input).await?;

// Tạo Merkle tree
let merkle_tree = create_merkle_tree(&batch.orders);
let merkle_root = merkle_tree.root();
```

#### **C. Assessor Proving**
```rust
// Tạo assessor proof cho mỗi order
for order in &batch.orders {
    let assessor_input = AssessorInput {
        fulfillment: create_fulfillment(&order),
        domain: eip712_domain(market_address, chain_id),
    };
    
    let assessor_proof = prover.prove_assessor(assessor_input).await?;
    order.assessor_proof = Some(assessor_proof);
}
```

### **7. 📤 Submission Process**

#### **A. Prepare Fulfillment Data**
```rust
// Tạo fulfillment cho mỗi order
let fulfillments = batch.orders.iter().map(|order| {
    Fulfillment {
        requestId: order.request.id,
        prover: prover_address,
        proof: order.merkle_inclusion_proof,
        journal: order.journal,
        callback: order.request.requirements.callback,
    }
}).collect();
```

#### **B. Submit to Market Contract**
```rust
// Submit batch fulfillment
let tx = market.fulfillBatch(
    fulfillments,
    aggregation_proof,
    merkle_root
).with_gas_limit(estimated_gas * fulfillments.len());

let receipt = tx.send().await?;
```

### **8. ✅ Verification & Payment**

#### **A. On-chain Verification**
```solidity
// Market contract verify
function fulfillBatch(Fulfillment[] fulfillments, bytes proof, bytes32 root) {
    // 1. Verify aggregation proof
    require(verifier.verify(proof, root), "Invalid aggregation proof");
    
    // 2. Verify each fulfillment
    for (uint i = 0; i < fulfillments.length; i++) {
        Fulfillment memory f = fulfillments[i];
        
        // Verify Merkle inclusion
        require(verifyMerkleProof(f.proof, f.journal, root), "Invalid inclusion");
        
        // Verify predicate
        require(f.request.requirements.predicate.eval(f.journal), "Predicate failed");
        
        // Execute callback if needed
        if (f.callback != address(0)) {
            f.callback.call(f.journal);
        }
        
        // Mark as fulfilled and pay prover
        requests[f.requestId].fulfilled = true;
        payable(f.prover).transfer(f.request.offer.price);
    }
}
```

#### **B. Payment Distribution**
```rust
// Prover nhận payment
for order in &batch.orders {
    let payment = order.lock_price;
    let gas_refund = estimate_gas_cost(&order);
    let net_profit = payment - gas_refund - proving_cost;
    
    tracing::info!("Order {} fulfilled: {} ETH profit", order.id(), net_profit);
}

// Return stake
let total_stake = batch.orders.iter().sum(|o| o.request.offer.lockStake);
stake_balance += total_stake;
```

## 🔄 State Transitions

```
Order States:
New → Pricing → Priced → Locked → Proving → Proven → Aggregating → Submitted → Fulfilled

Batch States:
Aggregating → PendingCompression → Complete → PendingSubmission → Submitted
```

## ⏱️ Timing Considerations

### **Critical Timeouts:**
- **Lock Timeout**: Thời gian tối đa để lock order
- **Proving Timeout**: Thời gian tối đa để hoàn thành proving
- **Submission Timeout**: Thời gian tối đa để submit proof

### **Optimization Points:**
- **Early Bidding**: Bid ở 25% ramp time thay vì 50%
- **Fast Preflight**: Tối ưu tốc độ đánh giá order
- **Batch Efficiency**: Tối ưu kích thước batch
- **Gas Optimization**: Sử dụng priority gas hợp lý

## 🚨 Error Handling

### **Common Failures:**
1. **Lock Failed**: Order đã bị prover khác lock
2. **Proving Failed**: Lỗi trong quá trình prove
3. **Timeout**: Vượt quá thời gian cho phép
4. **Verification Failed**: Proof không hợp lệ
5. **Gas Issues**: Không đủ gas hoặc gas price thấp

### **Recovery Strategies:**
- **Retry Logic**: Retry với backoff
- **Fallback Options**: Chuyển sang order khác
- **Stake Recovery**: Claim lại stake nếu có lỗi
- **Monitoring**: Alert khi có vấn đề

## 📊 Performance Metrics

### **Key Metrics:**
- **Lock Success Rate**: % order lock thành công
- **Proving Time**: Thời gian trung bình để prove
- **Batch Efficiency**: Số order per batch
- **Profit Margin**: Lợi nhuận trên mỗi order
- **Gas Efficiency**: Chi phí gas per order

### **Monitoring Commands:**
```bash
# Monitor order status
sqlite3 broker.db "SELECT status, COUNT(*) FROM orders GROUP BY status;"

# Check recent performance
sqlite3 broker.db "SELECT 
    AVG(proving_time) as avg_proving_time,
    AVG(lock_price) as avg_price,
    COUNT(*) as total_orders
FROM orders 
WHERE status = 'Fulfilled' 
AND updated_at > datetime('now', '-1 day');"

# Monitor batch efficiency
sqlite3 broker.db "SELECT 
    AVG(order_count) as avg_batch_size,
    AVG(submission_time - created_at) as avg_batch_time
FROM batches 
WHERE status = 'Submitted';"
```

---

**Tóm tắt**: Quy trình prove bao gồm 8 bước chính từ request đến payment, với nhiều tối ưu hóa có thể áp dụng ở mỗi bước để tăng hiệu quả cạnh tranh.