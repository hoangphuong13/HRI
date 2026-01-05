import pandas as pd
import matplotlib.pyplot as plt
import numpy as np

# ======================================================
# 🔴 1. THAY TÊN FILE CSV CỦA BẠN
FILE_PATH = 'report_data_20260102_163614.csv' 

# 🔴 2. NHẬP SỐ GIÂY MUỐN CẮT BỎ (Nhìn vào ảnh cũ để chọn)
# Ví dụ: Dữ liệu bắt đầu đẹp từ giây thứ 7, hãy điền số 7
CUT_OFF_SECONDS = 7.0 
# ======================================================

def plot_trimmed_chart(file_path, cut_off):
    try:
        # --- 1. ĐỌC VÀ XỬ LÝ DỮ LIỆU ---
        print("Đang xử lý dữ liệu...")
        df = pd.read_csv(file_path)
        
        # Tính thời gian gốc
        df['Time_Obj'] = pd.to_datetime(df['Timestamp'], format='%H:%M:%S.%f')
        start_time_original = df['Time_Obj'].iloc[0]
        df['Original_Seconds'] = (df['Time_Obj'] - start_time_original).dt.total_seconds()
        
        # --- 2. CẮT VÀ RESET THỜI GIAN (QUAN TRỌNG) ---
        # Chỉ lấy những dòng sau giây thứ CUT_OFF_SECONDS
        df_new = df[df['Original_Seconds'] >= cut_off].copy()
        
        if df_new.empty:
            print("❌ Lỗi: Bạn cắt hết dữ liệu rồi! Hãy giảm số CUT_OFF_SECONDS xuống.")
            return

        # Reset lại thời gian: Dòng đầu tiên bây giờ sẽ là 0.0s
        new_start_time = df_new['Time_Obj'].iloc[0]
        df_new['Seconds'] = (df_new['Time_Obj'] - new_start_time).dt.total_seconds()
        
        # Lọc dữ liệu khoảng cách (để vẽ)
        df_dist_valid = df_new[df_new['Distance_m'] > 0]

        # Tính lại thống kê cho đoạn dữ liệu mới
        avg_latency = df_new['Processing_Time_ms'].mean()
        jitter = df_new['Processing_Time_ms'].std()
        avg_fps = df_new['FPS'].mean()

        # --- 3. VẼ BIỂU ĐỒ (GIỐNG CODE TRƯỚC) ---
        fig, ax1 = plt.subplots(figsize=(12, 7))
        
        # Tiêu đề cập nhật theo dữ liệu đã cắt
        plt.title(f"Đánh giá độ ổn định (Stability) và khả năng đáp ứng (Responsiveness) (Đã lọc nhiễu)\n(Avg Latency: {avg_latency:.1f}ms | Avg FPS: {avg_fps:.1f})", 
                 fontsize=14, fontweight='bold')
        plt.grid(True, axis='x', linestyle='--', alpha=0.5)

        # TRỤC 1: LATENCY (Đỏ)
        color_lat = '#d62728'
        ax1.set_xlabel('Thời gian (Giây) - Bắt đầu từ lúc phát hiện', fontsize=12)
        ax1.set_ylabel('Độ trễ (ms)', color=color_lat, fontweight='bold')
        ax1.plot(df_new['Seconds'], df_new['Processing_Time_ms'], color=color_lat, linewidth=1.5, alpha=0.6, label='Processing Time')
        ax1.axhline(y=33.3, color='black', linestyle='--', linewidth=1.5, label='Deadline (33ms)')
        ax1.tick_params(axis='y', labelcolor=color_lat)
        ax1.set_ylim(0, 60) # Zoom vào khoảng quan trọng

        # TRỤC 2: FPS (Xanh dương)
        ax2 = ax1.twinx()
        color_fps = '#1f77b4'
        ax2.set_ylabel('FPS', color=color_fps, fontweight='bold')
        ax2.plot(df_new['Seconds'], df_new['FPS'], color=color_fps, linestyle=':', alpha=0.7, label='FPS')
        ax2.tick_params(axis='y', labelcolor=color_fps)
        ax2.set_ylim(0, 40)

        # TRỤC 3: KHOẢNG CÁCH (Xanh lá)
        ax3 = ax1.twinx()
        color_dist = '#2ca02c'
        ax3.spines.right.set_position(("axes", 1.1)) 
        ax3.set_ylabel('Khoảng cách (m)', color=color_dist, fontweight='bold')
        ax3.scatter(df_dist_valid['Seconds'], df_dist_valid['Distance_m'], color=color_dist, s=25, label='Distance')
        ax3.tick_params(axis='y', labelcolor=color_dist)
        ax3.set_ylim(0, 4.0)

        # Chú giải
        lines = [plt.Line2D([0], [0], color=color_lat, lw=2),
                 plt.Line2D([0], [0], color='black', linestyle='--', lw=2),
                 plt.Line2D([0], [0], color=color_fps, linestyle=':', lw=2),
                 plt.Line2D([0], [0], marker='o', color=color_dist, linestyle='None')]
        labels = ['Latency', 'Deadline (33ms)', 'FPS', 'Distance']
        ax1.legend(lines, labels, loc='upper left')

        plt.tight_layout()
        plt.savefig('Bao_cao_Cat_Data.png', dpi=300)
        print("✅ Đã vẽ xong! Biểu đồ mới bắt đầu từ 0.0s (tức giây thứ 7 cũ).")
        plt.show()

    except Exception as e:
        print(f"Lỗi: {e}")

if __name__ == "__main__":
    plot_trimmed_chart(FILE_PATH, CUT_OFF_SECONDS)