clc; clear;

portName = "COM4";
baudRate = 115200;
N = 256;

com = serialport(portName, baudRate);
com.Timeout = 2;
flush(com);

fprintf("Opened %s @ %d baud\n", portName, baudRate);

tx = uint8(0:N-1);
write(com, tx, "uint8");
fprintf("Sent %d bytes\n", numel(tx));

rx = uint8([]);
t0 = tic;
while numel(rx) < N && toc(t0) < com.Timeout
    a = com.NumBytesAvailable;
    if a > 0
        chunk = read(com, a, "uint8");
        rx = [rx; chunk(:)];  % <-- FIX: force column
    end
end

fprintf("Received %d bytes\n", numel(rx));

nCompare = min(numel(tx), numel(rx));
if nCompare == 0
    fprintf("No data received.\n");
else
    match = isequal(tx(1:nCompare).', rx(1:nCompare)); % tx as column for compare
    fprintf("Match on first %d bytes? %d\n", nCompare, match);

    if ~match
        idx = find(uint8(tx(1:nCompare).') ~= rx(1:nCompare), 1, "first");
        fprintf("First mismatch at index %d: sent=%d received=%d\n", idx-1, tx(idx), rx(idx));
    end
end

clear com;
