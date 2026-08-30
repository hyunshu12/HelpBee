import 'package:flutter/material.dart';

import '../data/booth_case.dart';

class PickerScreen extends StatelessWidget {
  const PickerScreen({super.key, required this.cases, required this.onPick});

  final List<BoothCase> cases;
  final ValueChanged<BoothCase> onPick;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        children: [
          Text(
            '벌통 사진을 하나 골라보세요',
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          const SizedBox(height: 32),
          Expanded(
            child: GridView.count(
              crossAxisCount: 2,
              mainAxisSpacing: 24,
              crossAxisSpacing: 24,
              childAspectRatio: 16 / 9,
              children: [
                for (final c in cases)
                  // 티어·점수를 쓰지 않는다. 관람객이 답을 미리 알면 추측이 무의미해진다.
                  InkWell(
                    onTap: () => onPick(c),
                    borderRadius: BorderRadius.circular(20),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Image.asset(
                        'assets/${c.photo}',
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
