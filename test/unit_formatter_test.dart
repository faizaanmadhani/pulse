import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_training_hub/models/activity.dart';
import 'package:pulse_training_hub/utils/unit_formatter.dart';

void main() {
  group('UnitFormatter constants', () {
    test('exposes expected conversion factors', () {
      expect(UnitFormatter.kmToMiles, 0.621371);
      expect(UnitFormatter.metersToFeet, 3.28084);
      expect(UnitFormatter.metersToYards, 1.09361);
    });
  });

  group('UnitFormatter.convertDistance', () {
    test('converts non-swim distance between km and mi', () {
      expect(UnitFormatter.convertDistance(10.0, UnitSystem.metric), 10.0);
      expect(
        UnitFormatter.convertDistance(10.0, UnitSystem.imperial),
        closeTo(6.21371, 1e-6),
      );
    });

    test('converts swim distance to meters and yards', () {
      expect(
        UnitFormatter.convertDistance(1.5, UnitSystem.metric, isSwim: true),
        1500.0,
      );
      expect(
        UnitFormatter.convertDistance(1.5, UnitSystem.imperial, isSwim: true),
        closeTo(1640.415, 1e-4),
      );
    });

    test('handles non-finite distances safely', () {
      expect(UnitFormatter.convertDistance(double.nan, UnitSystem.metric), 0.0);
      expect(
        UnitFormatter.convertDistance(
          double.infinity,
          UnitSystem.imperial,
          isSwim: true,
        ),
        0.0,
      );
    });
  });

  group('UnitFormatter.formatDistance', () {
    test('formats metric and imperial run/bike distances', () {
      expect(
        UnitFormatter.formatDistance(10.2, UnitSystem.metric),
        '10.2 km',
      );
      expect(
        UnitFormatter.formatDistance(10.2, UnitSystem.imperial),
        '6.3 mi',
      );
      expect(
        UnitFormatter.formatDistance(
          42.195,
          UnitSystem.imperial,
          discipline: SportDiscipline.run,
          decimals: 2,
        ),
        '26.22 mi',
      );
      expect(
        UnitFormatter.formatDistance(
          1250.4,
          UnitSystem.metric,
          discipline: SportDiscipline.bike,
        ),
        '1,250.4 km',
      );
      expect(
        UnitFormatter.formatDistance(
          10.2,
          UnitSystem.metric,
          decimals: 0,
        ),
        '10 km',
      );
    });

    test('formats swim distances in meters and yards', () {
      expect(
        UnitFormatter.formatDistance(
          1.5,
          UnitSystem.metric,
          discipline: SportDiscipline.swim,
        ),
        '1,500 m',
      );
      expect(
        UnitFormatter.formatDistance(
          1.5,
          UnitSystem.imperial,
          discipline: SportDiscipline.swim,
        ),
        '1,640 yd',
      );
      expect(
        UnitFormatter.formatDistance(
          0.75,
          UnitSystem.metric,
          discipline: SportDiscipline.swim,
        ),
        '750 m',
      );
      expect(
        UnitFormatter.formatDistance(
          0.75,
          UnitSystem.imperial,
          discipline: SportDiscipline.swim,
        ),
        '820 yd',
      );
    });
  });

  group('UnitFormatter.formatElevation', () {
    test('formats metric meters and imperial feet with grouping', () {
      expect(UnitFormatter.formatElevation(914, UnitSystem.metric), '914 m');
      expect(
        UnitFormatter.formatElevation(914, UnitSystem.imperial),
        '2,999 ft',
      );
      expect(
        UnitFormatter.formatElevation(1250, UnitSystem.metric),
        '1,250 m',
      );
      expect(UnitFormatter.formatElevation(0, UnitSystem.imperial), '0 ft');
      expect(
        UnitFormatter.formatElevation(double.nan, UnitSystem.metric),
        '0 m',
      );
    });
  });

  group('UnitFormatter.formatPaceOrSpeed', () {
    test('formats run pace in /km and /mi', () {
      // 4:00 /km => 1000 / 240 = 4.1666667 m/s
      const runSpeedMps = 1000.0 / 240.0;
      expect(
        UnitFormatter.formatPaceOrSpeed(
          SportDiscipline.run,
          runSpeedMps,
          UnitSystem.metric,
        ),
        '4:00 /km',
      );
      // 240 / 0.621371 = 386.242679 s/mi => 6:26 /mi
      expect(
        UnitFormatter.formatPaceOrSpeed(
          SportDiscipline.run,
          runSpeedMps,
          UnitSystem.imperial,
        ),
        '6:26 /mi',
      );
    });

    test('rolls over 59.6 seconds to the next minute instead of :60', () {
      // 299.8 seconds per km should round to 300s => 5:00 /km
      const speedMps = 1000.0 / 299.8;
      expect(
        UnitFormatter.formatPaceOrSpeed(
          SportDiscipline.run,
          speedMps,
          UnitSystem.metric,
        ),
        '5:00 /km',
      );
    });

    test('formats bike and indoorBike speed in km/h and mph', () {
      // 10 m/s = 36.0 km/h = 22.369356 mph -> 22.4 mph
      expect(
        UnitFormatter.formatPaceOrSpeed(
          SportDiscipline.bike,
          10.0,
          UnitSystem.metric,
        ),
        '36.0 km/h',
      );
      expect(
        UnitFormatter.formatPaceOrSpeed(
          SportDiscipline.bike,
          10.0,
          UnitSystem.imperial,
        ),
        '22.4 mph',
      );
      expect(
        UnitFormatter.formatPaceOrSpeed(
          SportDiscipline.indoorBike,
          9.0,
          UnitSystem.metric,
        ),
        '32.4 km/h',
      );
      expect(
        UnitFormatter.formatPaceOrSpeed(
          SportDiscipline.indoorBike,
          9.0,
          UnitSystem.imperial,
        ),
        '20.1 mph',
      );
    });

    test('formats swim pace in /100m and /100yd', () {
      // 1.0 m/s => 100s / 100m = 1:40 /100m; 100 / 1.09361 = 91.44s / 100yd = 1:31 /100yd
      expect(
        UnitFormatter.formatPaceOrSpeed(
          SportDiscipline.swim,
          1.0,
          UnitSystem.metric,
        ),
        '1:40 /100m',
      );
      expect(
        UnitFormatter.formatPaceOrSpeed(
          SportDiscipline.swim,
          1.0,
          UnitSystem.imperial,
        ),
        '1:31 /100yd',
      );
    });

    test('returns em-dash for strength or invalid speeds', () {
      expect(
        UnitFormatter.formatPaceOrSpeed(
          SportDiscipline.strength,
          3.0,
          UnitSystem.metric,
        ),
        '—',
      );
      expect(
        UnitFormatter.formatPaceOrSpeed(
          SportDiscipline.run,
          0.0,
          UnitSystem.metric,
        ),
        '—',
      );
      expect(
        UnitFormatter.formatPaceOrSpeed(
          SportDiscipline.bike,
          -2.5,
          UnitSystem.imperial,
        ),
        '—',
      );
      expect(
        UnitFormatter.formatPaceOrSpeed(
          SportDiscipline.swim,
          double.nan,
          UnitSystem.metric,
        ),
        '—',
      );
    });
  });

  group('UnitFormatter.formatPaceFromDistanceAndDuration', () {
    test('computes speed and delegates to formatPaceOrSpeed', () {
      // 10 km in 45 min (2700s) => 4:30 /km, 7:15 /mi
      expect(
        UnitFormatter.formatPaceFromDistanceAndDuration(
          SportDiscipline.run,
          10.0,
          2700.0,
          UnitSystem.metric,
        ),
        '4:30 /km',
      );
      expect(
        UnitFormatter.formatPaceFromDistanceAndDuration(
          SportDiscipline.run,
          10.0,
          2700.0,
          UnitSystem.imperial,
        ),
        '7:15 /mi',
      );

      // 40 km bike in 1h 15m (4500s) => 32.0 km/h, 19.9 mph
      expect(
        UnitFormatter.formatPaceFromDistanceAndDuration(
          SportDiscipline.bike,
          40.0,
          4500.0,
          UnitSystem.metric,
        ),
        '32.0 km/h',
      );
      expect(
        UnitFormatter.formatPaceFromDistanceAndDuration(
          SportDiscipline.bike,
          40.0,
          4500.0,
          UnitSystem.imperial,
        ),
        '19.9 mph',
      );

      // 1.5 km swim in 25 min (1500s) => 1.0 m/s => 1:40 /100m, 1:31 /100yd
      expect(
        UnitFormatter.formatPaceFromDistanceAndDuration(
          SportDiscipline.swim,
          1.5,
          1500.0,
          UnitSystem.metric,
        ),
        '1:40 /100m',
      );
      expect(
        UnitFormatter.formatPaceFromDistanceAndDuration(
          SportDiscipline.swim,
          1.5,
          1500.0,
          UnitSystem.imperial,
        ),
        '1:31 /100yd',
      );

      // Strength and invalid inputs
      expect(
        UnitFormatter.formatPaceFromDistanceAndDuration(
          SportDiscipline.strength,
          0.0,
          2700.0,
          UnitSystem.metric,
        ),
        '—',
      );
      expect(
        UnitFormatter.formatPaceFromDistanceAndDuration(
          SportDiscipline.run,
          0.0,
          2700.0,
          UnitSystem.metric,
        ),
        '—',
      );
      expect(
        UnitFormatter.formatPaceFromDistanceAndDuration(
          SportDiscipline.run,
          5.0,
          0.0,
          UnitSystem.metric,
        ),
        '—',
      );
    });
  });

  group('UnitFormatter.formatStrengthDuration', () {
    test('formats unambiguous strength durations', () {
      expect(UnitFormatter.formatStrengthDuration(0), '0 min');
      expect(UnitFormatter.formatStrengthDuration(-60), '0 min');
      expect(UnitFormatter.formatStrengthDuration(double.nan), '0 min');
      expect(UnitFormatter.formatStrengthDuration(45 * 60), '45 min');
      expect(UnitFormatter.formatStrengthDuration(60 * 60), '1h');
      expect(UnitFormatter.formatStrengthDuration(75 * 60), '1h 15m');
      expect(UnitFormatter.formatStrengthDuration(80 * 60), '1h 20m');
    });
  });

  group('UnitFormatter.formatPercent', () {
    test('rounds floating-point precision artifacts cleanly', () {
      expect(UnitFormatter.formatPercent(8.489999771118164), '8.5%');
      expect(UnitFormatter.formatPercent(0.0), '0.0%');
      expect(UnitFormatter.formatPercent(100.0, decimals: 0), '100%');
      expect(UnitFormatter.formatPercent(12.3456, decimals: 2), '12.35%');
      expect(UnitFormatter.formatPercent(double.nan), '0.0%');
    });
  });

  group('UnitFormatter unit labels', () {
    test('returns expected labels for metric and imperial', () {
      expect(UnitFormatter.distanceUnitLabel(UnitSystem.metric), 'km');
      expect(UnitFormatter.distanceUnitLabel(UnitSystem.imperial), 'mi');
      expect(
        UnitFormatter.distanceUnitLabel(UnitSystem.metric, isSwim: true),
        'm',
      );
      expect(
        UnitFormatter.distanceUnitLabel(UnitSystem.imperial, isSwim: true),
        'yd',
      );

      expect(UnitFormatter.elevationUnitLabel(UnitSystem.metric), 'm');
      expect(UnitFormatter.elevationUnitLabel(UnitSystem.imperial), 'ft');

      expect(UnitFormatter.speedUnitLabel(UnitSystem.metric), 'km/h');
      expect(UnitFormatter.speedUnitLabel(UnitSystem.imperial), 'mph');

      expect(UnitFormatter.paceUnitLabel(UnitSystem.metric), '/km');
      expect(UnitFormatter.paceUnitLabel(UnitSystem.imperial), '/mi');
      expect(
        UnitFormatter.paceUnitLabel(UnitSystem.metric, isSwim: true),
        '/100m',
      );
      expect(
        UnitFormatter.paceUnitLabel(UnitSystem.imperial, isSwim: true),
        '/100yd',
      );
    });
  });
}
