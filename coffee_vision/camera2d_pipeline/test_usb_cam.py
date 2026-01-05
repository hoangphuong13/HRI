import cv2

def try_open_camera(index):
    print(f"--- Thử mở camera index {index} ---")
    cap = cv2.VideoCapture(index, cv2.CAP_DSHOW)  # Dùng DirectShow cho Windows
    if not cap.isOpened():
        print(f"Camera {index}: KHÔNG mở được.\n")
        return

    ret, frame = cap.read()
    if not ret or frame is None:
        print(f"Camera {index}: MỞ ĐƯỢC nhưng KHÔNG đọc được frame.\n")
    else:
        print(f"Camera {index}: ĐỌC ĐƯỢC frame OK ✅\n")
        cv2.imshow(f"Camera {index}", frame)
        print("Nhấn phím bất kỳ để đóng cửa sổ preview...")
        cv2.waitKey(0)

    cap.release()
    cv2.destroyAllWindows()


def main():
    # Thử lần lượt vài index phổ biến
    for idx in range(5):
        try_open_camera(idx)


if __name__ == "__main__":
    main()
