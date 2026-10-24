/// Kanał (kamera) znaleziony w rejestratorze NVR/DVR.
class DiscoveredChannel {
  const DiscoveredChannel(this.channel, this.name, {this.online});

  /// Numer kanału tak, jak używa go aplikacja (od 1).
  final int channel;
  final String name;

  /// true = kamera podłączona, false = brak sygnału, null = rejestrator nie podał stanu.
  final bool? online;

  DiscoveredChannel withOnline(bool? value) => DiscoveredChannel(channel, name, online: value);

  @override
  bool operator ==(Object other) =>
      other is DiscoveredChannel && other.channel == channel && other.name == name && other.online == online;

  @override
  int get hashCode => Object.hash(channel, name, online);

  @override
  String toString() => 'DiscoveredChannel($channel, $name, online: $online)';
}
