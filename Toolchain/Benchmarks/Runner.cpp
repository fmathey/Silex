#include <algorithm>
#include <chrono>
#include <cmath>
#include <cstdlib>
#include <iomanip>
#include <iostream>
#include <string>
#include <string_view>
#include <vector>

struct Summary {
    double minimum;
    double median;
    double percentile90;
    double maximum;
};

static bool measureOnce(const char* executable, double& milliseconds) {
    const char* nullDevice =
#if defined(_WIN32)
        "NUL";
#else
        "/dev/null";
#endif
    const std::string command = std::string{executable} + " > " + nullDevice;
    const auto start = std::chrono::steady_clock::now();
    const int status = std::system(command.c_str());
    const auto end = std::chrono::steady_clock::now();
    if (status != 0) {
        std::cerr << "benchmark process failed: " << executable << '\n';
        return false;
    }
    milliseconds = std::chrono::duration<double, std::milli>(end - start).count();
    return true;
}

static double percentile(const std::vector<double>& sorted, double fraction) {
    const double position = fraction * static_cast<double>(sorted.size() - 1);
    const std::size_t lower = static_cast<std::size_t>(std::floor(position));
    const std::size_t upper = static_cast<std::size_t>(std::ceil(position));
    const double weight = position - static_cast<double>(lower);
    return sorted[lower] * (1.0 - weight) + sorted[upper] * weight;
}

static Summary summarize(const std::vector<double>& values) {
    std::vector<double> sorted = values;
    std::ranges::sort(sorted);
    return Summary {
        sorted.front(),
        percentile(sorted, 0.5),
        percentile(sorted, 0.9),
        sorted.back(),
    };
}

static void printSummary(std::string_view label, const Summary& summary) {
    std::cout << label << ": median " << summary.median
              << " ms, p90 " << summary.percentile90
              << " ms, range [" << summary.minimum
              << ", " << summary.maximum << "] ms\n";
}

static bool warmUp(const char* first, const char* second, int count) {
    double ignored = 0.0;
    for (int iteration = 0; iteration < count; ++iteration) {
        if (!measureOnce(first, ignored)) return false;
        if (second != nullptr && !measureOnce(second, ignored)) return false;
    }
    return true;
}

int main(int argc, char** argv) {
    if (argc != 4) {
        std::cerr << "usage: integer-benchmark-runner <silex> <equivalent-cpp> <process-baseline>\n";
        return 1;
    }

    constexpr int warmupCount = 5;
    constexpr int sampleCount = 31;
    if (!warmUp(argv[3], nullptr, warmupCount)) return 1;
    if (!warmUp(argv[1], argv[2], warmupCount)) return 1;

    std::vector<double> processSamples;
    std::vector<double> silexSamples;
    std::vector<double> cppSamples;
    processSamples.reserve(sampleCount);
    silexSamples.reserve(sampleCount);
    cppSamples.reserve(sampleCount);

    for (int sample = 0; sample < sampleCount; ++sample) {
        double duration = 0.0;
        if (!measureOnce(argv[3], duration)) return 1;
        processSamples.push_back(duration);

        if (sample % 2 == 0) {
            if (!measureOnce(argv[1], duration)) return 1;
            silexSamples.push_back(duration);
            if (!measureOnce(argv[2], duration)) return 1;
            cppSamples.push_back(duration);
        } else {
            if (!measureOnce(argv[2], duration)) return 1;
            cppSamples.push_back(duration);
            if (!measureOnce(argv[1], duration)) return 1;
            silexSamples.push_back(duration);
        }
    }

    std::vector<double> pairedDifferences;
    pairedDifferences.reserve(sampleCount);
    for (int sample = 0; sample < sampleCount; ++sample) {
        pairedDifferences.push_back(silexSamples[sample] - cppSamples[sample]);
    }

    const Summary processSummary = summarize(processSamples);
    const Summary silexSummary = summarize(silexSamples);
    const Summary cppSummary = summarize(cppSamples);
    const Summary differenceSummary = summarize(pairedDifferences);
    const double differencePercent = differenceSummary.median / cppSummary.median * 100.0;

    std::cout << std::fixed << std::setprecision(3);
    std::cout << sampleCount << " measured samples after " << warmupCount << " warmups\n";
    printSummary("Process baseline", processSummary);
    printSummary("Silex", silexSummary);
    printSummary("Equivalent C++", cppSummary);
    std::cout << "Paired median delta: " << differenceSummary.median
              << " ms (" << differencePercent << "%)\n";
}
