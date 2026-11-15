#import "TorrentBridge.h"
#include <libtorrent/session.hpp>
#include <libtorrent/session_params.hpp>
#include <libtorrent/settings_pack.hpp>
#include <libtorrent/magnet_uri.hpp>
#include <libtorrent/torrent_info.hpp>
#include <libtorrent/torrent_handle.hpp>
#include <libtorrent/torrent_status.hpp>
#include <libtorrent/torrent_flags.hpp>
#include <libtorrent/alert_types.hpp>
#include <libtorrent/announce_entry.hpp>
#include <atomic>
#include <chrono>
#include <mutex>
#include <thread>
#include <algorithm>
#include <stdexcept>

namespace lt = libtorrent;
using Clock = std::chrono::steady_clock;
static void Report(NSError **error, std::string const& text) {
    if (error) *error = [NSError errorWithDomain:@"WatchlyTorrent" code:1
        userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithUTF8String:text.c_str()] ?: @"Torrent error"}];
}

@implementation WLTorrentBridge {
    std::unique_ptr<lt::session> _session;
    lt::torrent_handle _handle;
    std::shared_ptr<const lt::torrent_info> _info;
    std::mutex _mutex;
    std::atomic<bool> _cancelled;
    std::string _directory;
    int64_t _cap;
    int _selected;
    int _zone;
    int _cachedPiece;
    NSData *_pieceData;
}
- (instancetype)initWithDirectory:(NSString *)directory cacheBytes:(int64_t)cacheBytes {
    if ((self = [super init])) {
        _directory = directory.UTF8String;
        _cap = std::max<int64_t>(512LL * 1024 * 1024, cacheBytes);
        _selected = -1; _zone = -1; _cachedPiece = -1; _cancelled = false;
    }
    return self;
}
- (void)checkCancelled {
    if (_cancelled) throw std::runtime_error("Playback cancelled.");
}
- (void)checkStatus {
    [self checkCancelled];
    if (!_handle.is_valid()) throw std::runtime_error("No torrent is open.");
    auto status = _handle.status();
    if (status.errc) throw std::runtime_error(status.errc.message());
}
- (void)configureParams:(lt::add_torrent_params&)params {
    params.save_path = _directory;
    params.flags &= ~(lt::torrent_flags::paused | lt::torrent_flags::auto_managed);
    params.flags |= lt::torrent_flags::default_dont_download;
    params.trackers.push_back("udp://tracker.opentrackr.org:1337/announce");
    params.trackers.push_back("udp://tracker.torrent.eu.org:451/announce");
    if (params.ti) params.file_priorities.assign(params.ti->num_files(), lt::dont_download);
}
- (BOOL)open:(NSString *)source error:(NSError **)error {
    std::lock_guard<std::mutex> guard(_mutex);
    try {
        [self checkCancelled];
        if (_session) throw std::runtime_error("This streaming session is already open.");
        lt::settings_pack settings;
        settings.set_str(lt::settings_pack::user_agent, "Watchly-tvOS/0.1 libtorrent/2.0");
        settings.set_str(lt::settings_pack::listen_interfaces, "0.0.0.0:6881,[::]:6881");
        settings.set_str(lt::settings_pack::dht_bootstrap_nodes,
            "router.bittorrent.com:6881,router.utorrent.com:6881,dht.transmissionbt.com:6881");
        settings.set_bool(lt::settings_pack::enable_dht, true);
        settings.set_int(lt::settings_pack::connections_limit, 100);
        settings.set_int(lt::settings_pack::alert_mask,
            static_cast<int>(static_cast<std::uint32_t>(lt::alert_category::error | lt::alert_category::storage | lt::alert_category::status)));
        NSString *certificates = [[NSBundle mainBundle] pathForResource:@"cacert" ofType:@"pem"];
        if (certificates) setenv("SSL_CERT_FILE", certificates.UTF8String, 1);
        _session = std::make_unique<lt::session>(lt::session_params(settings));
        lt::add_torrent_params params;
        lt::error_code ec;
        if ([source.lowercaseString hasPrefix:@"magnet:"]) params = lt::parse_magnet_uri(source.UTF8String, ec);
        else params.ti = std::make_shared<lt::torrent_info>(source.UTF8String, ec);
        if (ec) throw std::runtime_error(ec.message());
        [self configureParams:params];
        _handle = _session->add_torrent(params, ec);
        if (ec) throw std::runtime_error(ec.message());
        return YES;
    } catch (std::exception const& e) { Report(error, e.what()); return NO; }
}
- (NSDictionary *)snapshot:(NSError **)error {
    std::lock_guard<std::mutex> guard(_mutex);
    try {
        [self checkStatus];
        auto status = _handle.status();
        _info = _handle.torrent_file();
        NSMutableArray *files = [NSMutableArray array];
        if (_info) {
            if (_info->piece_length() > 64 * 1024 * 1024) throw std::runtime_error("This torrent uses unusually large pieces and is not supported.");
            auto const& storage = _info->files();
            for (int i = 0; i < storage.num_files(); ++i) {
                lt::file_index_t index(i);
                if (storage.pad_file_at(index)) continue;
                NSString *name = [NSString stringWithUTF8String:storage.file_path(index).c_str()];
                if (name) [files addObject:@{@"index": @(i), @"name": name, @"size": @(storage.file_size(index))}];
            }
        }
        return @{@"hasMetadata": @(_info != nullptr), @"files": files,
            @"peers": @(status.num_peers), @"speed": @(status.download_payload_rate), @"downloaded": @(status.total_done)};
    } catch (std::exception const& e) { Report(error, e.what()); return nil; }
}
- (BOOL)selectFile:(NSInteger)index error:(NSError **)error {
    std::lock_guard<std::mutex> guard(_mutex);
    try {
        [self checkStatus];
        _info = _handle.torrent_file();
        if (!_info || index < 0 || index >= _info->num_files()) throw std::runtime_error("Invalid torrent file.");
        if (_info->files().file_size(lt::file_index_t(int(index))) <= 0) throw std::runtime_error("The selected file is empty.");
        _selected = int(index); _zone = -1; _cachedPiece = -1; _pieceData = nil;
        // Piece-level reads work even when libtorrent stores data in its partfile.
        // Do not promote a whole season pack to a nonzero file priority.
        return YES;
    } catch (std::exception const& e) { Report(error, e.what()); return NO; }
}
- (void)rollIfNeeded {
    if (_handle.status().total_done < _cap) return;
    auto info = _handle.torrent_file_with_hashes();
    if (!info) throw std::runtime_error("Torrent metadata disappeared.");
    auto old = _handle;
    _session->remove_torrent(old, lt::session::delete_files);
    auto deadline = Clock::now() + std::chrono::seconds(15);
    bool deleted = false;
    while (!deleted && Clock::now() < deadline) {
        [self checkCancelled];
        std::vector<lt::alert*> alerts;
        _session->pop_alerts(&alerts);
        for (auto *alert : alerts) {
            if (auto *done = lt::alert_cast<lt::torrent_deleted_alert>(alert)) {
                if (done->info_hashes == info->info_hashes()) deleted = true;
            }
            if (auto *failed = lt::alert_cast<lt::torrent_delete_failed_alert>(alert))
                throw std::runtime_error(failed->error.message());
        }
        if (!deleted) std::this_thread::sleep_for(std::chrono::milliseconds(50));
    }
    if (!deleted) throw std::runtime_error("Timed out freeing streaming storage. Close playback and retry.");
    lt::add_torrent_params params;
    params.ti = info;
    [self configureParams:params];
    lt::error_code ec;
    _handle = _session->add_torrent(params, ec);
    if (ec) throw std::runtime_error(ec.message());
    _info = info; _zone = -1; _cachedPiece = -1; _pieceData = nil;
}
- (void)prioritizeAt:(int)piece {
    const int length = _info->piece_length();
    const int first = int(_info->files().map_file(lt::file_index_t(_selected), 0, 1).piece);
    const int64_t size = _info->files().file_size(lt::file_index_t(_selected));
    const int last = int(_info->files().map_file(lt::file_index_t(_selected), size - 1, 1).piece);
    const int ahead = std::max(2, 32 * 1024 * 1024 / length);
    if (_zone < 0 || piece < _zone || piece > _zone + ahead / 2) {
        std::vector<lt::download_priority_t> priorities(_info->num_pieces(), lt::dont_download);
        for (int p = std::max(first, piece - 1); p <= std::min(last, piece + ahead); ++p) priorities[p] = lt::default_priority;
        priorities[first] = lt::default_priority;
        for (int p = std::max(first, last - std::max(1, 2 * 1024 * 1024 / length)); p <= last; ++p) priorities[p] = lt::default_priority;
        _handle.clear_piece_deadlines();
        _handle.prioritize_pieces(priorities);
        for (int p = piece; p <= std::min(last, piece + ahead); ++p) _handle.set_piece_deadline(lt::piece_index_t(p), (p - piece) * 250);
        _zone = piece;
    }
    _handle.set_piece_deadline(lt::piece_index_t(piece), 0);
}
- (NSData *)readAt:(int64_t)offset count:(NSInteger)count error:(NSError **)error {
    std::lock_guard<std::mutex> guard(_mutex);
    try {
        [self checkStatus];
        if (!_info || _selected < 0) throw std::runtime_error("Select a video first.");
        int64_t size = _info->files().file_size(lt::file_index_t(_selected));
        if (offset < 0 || offset >= size || count <= 0) throw std::runtime_error("Invalid video byte range.");
        [self rollIfNeeded];
        NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfFileSystemForPath:[NSString stringWithUTF8String:_directory.c_str()] error:nil];
        if (attributes && [attributes[NSFileSystemFreeSize] longLongValue] < 128LL * 1024 * 1024)
            throw std::runtime_error("Apple TV storage is nearly full. Free space and try again.");
        auto request = _info->files().map_file(lt::file_index_t(_selected), offset, 1);
        int piece = int(request.piece);
        [self prioritizeAt:piece];
        if (_cachedPiece != piece || !_pieceData) {
            auto deadline = Clock::now() + std::chrono::seconds(45);
            bool reading = false;
            _pieceData = nil;
            while (!_pieceData && Clock::now() < deadline) {
                [self checkStatus];
                if (!reading && _handle.have_piece(request.piece)) { _handle.read_piece(request.piece); reading = true; }
                std::vector<lt::alert*> alerts;
                _session->pop_alerts(&alerts);
                for (auto *alert : alerts) {
                    if (auto *read = lt::alert_cast<lt::read_piece_alert>(alert)) {
                        if (read->handle == _handle && read->piece == request.piece) {
                            if (read->error) throw std::runtime_error(read->error.message());
                            _pieceData = [NSData dataWithBytes:read->buffer.get() length:read->size];
                            _cachedPiece = piece;
                        }
                    }
                }
                if (!_pieceData) std::this_thread::sleep_for(std::chrono::milliseconds(50));
            }
            if (!_pieceData) throw std::runtime_error("Timed out waiting for torrent peers. Try a source with more seeders.");
        }
        auto available = int64_t(_pieceData.length) - request.start;
        auto amount = std::min<int64_t>({available, size - offset, int64_t(count), 256 * 1024});
        if (amount <= 0) throw std::runtime_error("Invalid piece data.");
        return [_pieceData subdataWithRange:NSMakeRange(request.start, NSUInteger(amount))];
    } catch (std::exception const& e) { Report(error, e.what()); return nil; }
}
- (void)cancel { _cancelled = true; }
- (void)stop {
    _cancelled = true;
    std::lock_guard<std::mutex> guard(_mutex);
    if (_session && _handle.is_valid()) _session->remove_torrent(_handle, lt::session::delete_files);
    _handle = {}; _info.reset(); _pieceData = nil; _session.reset();
}
@end
