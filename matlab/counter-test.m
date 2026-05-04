s = serialport("COM9", 12000000);
flush(s);

disp("Reading 4-byte counter chunks...");

while true
    if s.NumBytesAvailable >= 4
        data = read(s, 4, "uint8");

        disp("Bytes:");
        disp(data);


        fprintf("Byte 1: %02X\n", data(1));
        fprintf("Byte 2: %02X\n", data(2));
        fprintf("Byte 3: %02X\n", data(3));
        fprintf("Byte 4: %02X\n\n", data(4));

        %disp("Hex:");
        %disp(dec2hex(data));
    end

    pause(0.01);
end
