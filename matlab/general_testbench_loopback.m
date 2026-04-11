clc; clear;

%% Testing Settings (Change with different hardware + testing data)
portName = "COM5";      % USB COM Port
baudRate = 12000000;     % Baud Rate
dataPath = "row.mat";   % Data Path
trials = 20;            % Number of Trials
timeout_s = 2;          % Serial Port Timeout

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% Load Data File
s = load(dataPath);
vars = fieldnames(s);
bits = s.(vars{1});
bits = uint8(bits(:));

% Check conditions for valid binary file for testing
if any(bits ~= 0 & bits ~= 1)
    error("s.a must contain only 0's and 1's.")
end

numBits = numel(bits);
if mod(numBits, 8) ~= 0
    error("Number of bits (%d) is not divisible by 8.", numBits);
end

% Calculate bytes per trial
N = numBits / 8;    

bits8 = reshape(bits, 8, []).';
c = double([128;64;32;16;8;4;2;1]);
tx = uint8(double(bits8) * c);

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

%% Result Storage
receivedCount = zeros(trials,1); % How many bytes recieved
matchFlag     = false(trials,1); % Does rx match tx
duration_s    = zeros(trials,1); % How long to transmit bytes
firstBadIdx   = nan(trials,1);   % first mismatch index (0-based), NaN if none/unknown

%% Run Trials
fprintf("Running %d trials on %s at %d baud, N=%d bytes...\n\n", trials, portName, baudRate, N);


% For each trial:
for k = 1:trials

    tStart = tic;

    % Open new serial port
    com = serialport(portName, baudRate);
    com.Timeout = timeout_s;
    flush(com);

    % Send data through com port
    write(com, tx, "uint8");

    % Receive data until N or timeout
    rx = uint8([]);
    t0 = tic;
    % When all bytes have not been collected and timout wasn't exceeded
    while numel(rx) < N && toc(t0) < timeout_s
        a = com.NumBytesAvailable;
        % If there are awaiting bytes, append to rx
        if a > 0
            chunk = read(com, a, "uint8");
            rx = [rx; chunk(:)]; % consider allocating the size of it
        end
    end

    % Close port and report duration
    clear com;
    duration_s(k) = toc(tStart);

    % Record number of bytes recieved
    receivedCount(k) = numel(rx);


    if numel(rx) == N
        % Check if data sent matches data received
        same = isequal(tx(:), rx(:));
        matchFlag(k) = same;
    
        if ~same
            % Find first mismatch if wasn't transmited correctly
            idx = find(tx(:) ~= rx(:), 1, "first");
            firstBadIdx(k) = idx - 1;
        end
    else
        matchFlag(k) = false;
        % firstBadIdx stays NaN (we didn't even get N bytes)
    end

    % Quick progress line every trial
    fprintf("Trial %3d/%3d | recv=%3d | match=%d | dt=%.3fs\n", ...
        k, trials, receivedCount(k), matchFlag(k), duration_s(k));
    
end

%% Provide Testing Summary
% Calculate summary metrics
passStrict = (receivedCount == N) & matchFlag;
passRate = mean(passStrict) * 100;

avgRecv = mean(receivedCount);
minRecv = min(receivedCount);
maxRecv = max(receivedCount);

avgTime = mean(duration_s);
p95Time = prctile(duration_s, 95);

% Throughput estimates (based on actual bytes received per trial / duration)
throughput_Bps = receivedCount ./ duration_s;     % bytes/sec
avgThroughput = mean(throughput_Bps);
p05Throughput = prctile(throughput_Bps, 5);

% Mismatch / short-receive counts
nStrictPass = sum(passStrict);
nShort = sum(receivedCount < N);
nFullButMismatch = sum((receivedCount == N) & ~matchFlag);

% Print summary
fprintf("\n================ SUMMARY ================\n");
fprintf("Port: %s | Baud: %d | N: %d | Trials: %d\n", portName, baudRate, N, trials);
fprintf("STRICT PASS (recv==N AND match==1): %d/%d (%.1f%%)\n", nStrictPass, trials, passRate);
fprintf("Avg bytes received: %.1f (min=%d, max=%d)\n", avgRecv, minRecv, maxRecv);
fprintf("Short receives (<N): %d trials\n", nShort);
fprintf("Full receives (=N) but mismatch: %d trials\n", nFullButMismatch);
fprintf("Avg trial time: %.3fs (95th%%=%.3fs)\n", avgTime, p95Time);
fprintf("Avg throughput: %.0f B/s (5th%%=%.0f B/s)\n", avgThroughput, p05Throughput);

% If mismatches happened, show common first-bad positions
badIdx = firstBadIdx(~isnan(firstBadIdx));
if ~isempty(badIdx)
    fprintf("\nFirst mismatch index stats (0-based):\n");
    fprintf("  count=%d | min=%d | median=%d | max=%d\n", ...
        numel(badIdx), min(badIdx), round(median(badIdx)), max(badIdx));

    % show top 10 most common mismatched indices
    [u,~,ic] = unique(badIdx);
    counts = accumarray(ic, 1);
    [countsSorted, order] = sort(counts, "descend");
    top = min(10, numel(u));
    fprintf("  Most common first-bad indices:\n");
    for i = 1:top
        fprintf("    idx=%d occurred %d times\n", u(order(i)), countsSorted(i));
    end
end
fprintf("========================================\n");
