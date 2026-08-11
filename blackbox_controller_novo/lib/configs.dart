import 'package:flutter/material.dart';

class PresetConfig {
  String label;
  String subLabel;
  int blackboxPresetNumber;
  Color ledColor;
  List<bool> initialEffectsState;

  PresetConfig({
    required this.label,
    required this.subLabel,
    required this.blackboxPresetNumber,
    required this.ledColor,
    required this.initialEffectsState,
  });
}

class EffectBlockConfig {
  String name;
  int ccNumber;
  Color activeColor;
  bool isEnabled;

  EffectBlockConfig({
    required this.name,
    required this.ccNumber,
    required this.activeColor,
    required this.isEnabled,
  });
}

// ESTA CLASSE RETORNA O GRID QUE ESTAVA FALTANDO NA LINHA 230
// ESTA CLASSE GERE O GRID SEM CORTAR EM NENHUMA ORIENTAÇÃO
class CustomAppLayout {
  static Widget buildGrid(bool isLandscape, List<PresetConfig> presets, Widget Function(int) buildButton) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Calcula quantas colunas usar
        int crossAxisCount = isLandscape ? 4 : 2;
        
        // Calcula dinamicamente o espaço que cada botão deve ter sem estourar a tela
        double larguraDoBotao = constraints.maxWidth / crossAxisCount;
        double alturaDoBotao = isLandscape 
            ? (constraints.maxHeight / 2) - 10  // Deitado divide o espaço vertical por 2 linhas
            : (constraints.maxHeight / 4) - 10; // Em pé divide por 4 linhas

        // Evita divisões inválidas ou valores negativos
        double aspectoProporcional = (larguraDoBotao > 0 && alturaDoBotao > 0) 
            ? (larguraDoBotao / alturaDoBotao) 
            : (isLandscape ? 1.6 : 1.2);

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: aspectoProporcional, // Aplica a proporção inteligente calculada
          ),
          itemCount: presets.length,
          itemBuilder: (context, index) => buildButton(index),
        );
      },
    );
  }
}
