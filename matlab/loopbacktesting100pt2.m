clc; clear;

%% ===== USER SETTINGS =====
portName  = "COM4";
baudRate  = 230400;
N         = 32 %%256;
trials    = 100;
timeout_s = 2;

%% ===== OPEN PORT ONCE =====
com = serialport(portName, baudRate);
com.Timeout = timeout_s;
flush(com);

fprintf("Opened %s @ %d baud (keeping open)\n", portName, baudRate);
fprintf("Running %d trials, N=%d bytes each...\n\n", trials, N);

%% ===== RESULTS =====
receivedCount = zeros(trials,1);
matchFlag     = false(trials,1);
duration_s    = zeros(trials,1);
firstBadIdx   = nan(trials,1);

tx = uint8(0:N-1);  % fixed pattern every trial

for k = 1:trials
    tStart = tic;

    % Clear any leftover bytes from previous trial
    flush(com);

    % Send
    write(com, tx, "uint8");

    % Read until N or timeout
    rx = uint8([]);
    t0 = tic;
    while numel(rx) < N && toc(t0) < timeout_s
        a = com.NumBytesAvailable;
        if a > 0
            chunk = read(com, a, "uint8");
            rx = [rx; chunk(:)]; %#ok<AGROW>
        end
    end

    duration_s(k) = toc(tStart);
    receivedCount(k) = numel(rx);

    if numel(rx) == N
        same = isequal(tx(:), rx(:));
        matchFlag(k) = same;
        if ~same
            idx = find(tx(:) ~= rx(:), 1, "first");
            firstBadIdx(k) = idx - 1; % 0-based
        end
    end

    if mod(k,10) == 0
        fprintf("Trial %3d/%3d | recv=%3d | match=%d | dt=%.3fs\n", ...
            k, trials, receivedCount(k), matchFlag(k), duration_s(k));
    end
end

%% ===== SUMMARY =====
passStrict = (receivedCount == N) & matchFlag;
passRate = mean(passStrict) * 100;

avgRecv = mean(receivedCount);
minRecv = min(receivedCount);
maxRecv = max(receivedCount);

avgTime = mean(duration_s);
p95Time = prctile(duration_s, 95);

throughput_Bps = receivedCount ./ duration_s;
avgThroughput = mean(throughput_Bps);
p05Throughput = prctile(throughput_Bps, 5);

nStrictPass = sum(passStrict);
nShort = sum(receivedCount < N);
nFullButMismatch = sum((receivedCount == N) & ~matchFlag);

fprintf("\n================ SUMMARY (KEEP OPEN) ================\n");
fprintf("Port: %s | Baud: %d | N: %d | Trials: %d\n", portName, baudRate, N, trials);
fprintf("STRICT PASS (recv==N AND match==1): %d/%d (%.1f%%)\n", nStrictPass, trials, passRate);
fprintf("Avg bytes received: %.1f (min=%d, max=%d)\n", avgRecv, minRecv, maxRecv);
fprintf("Short receives (<N): %d trials\n", nShort);
fprintf("Full receives (=N) but mismatch: %d trials\n", nFullButMismatch);
fprintf("Avg trial time: %.3fs (95th%%=%.3fs)\n", avgTime, p95Time);
fprintf("Avg throughput: %.0f B/s (5th%%=%.0f B/s)\n", avgThroughput, p05Throughput);
fprintf("=====================================================\n");

%% ===== CLEANUP =====
clear com;
