#pragma once

#include <random>

// RAND/ANY ビルトイン、および Value::asString() の array→文字列（雑談配列のランダム選択）が
// 共有する乱数エンジン。SRAND(seed) はこのエンジンを再シードすることで、YAYA スクリプトから
// 見える全てのランダム選択（配列アクセスも含む）を決定的に再現可能にする。
// プロセスにつき VM は 1 インスタンスのみのため、関数ローカル static で単一エンジンとして共有する。
namespace yaya_rng {

inline std::mt19937& engine() {
    static std::mt19937 gen(std::random_device{}());
    return gen;
}

} // namespace yaya_rng
