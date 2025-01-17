import 'package:flutter/material.dart';

class PickerItem<T> extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Widget? leading;
  final IconData? trailingIcon;
  final void Function() onSelected;
  final bool? isSelected;

  const PickerItem({
    super.key,
    required this.label,
    required this.icon,
    required this.onSelected,
    this.isSelected,
    this.trailingIcon,
    this.leading,
  });

  @override
  Widget build(BuildContext context) {
    ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 10, right: 10),
      child: Material(
        borderRadius: BorderRadius.circular(50),
        color: isSelected == true ? theme.colorScheme.primaryContainer.withOpacity(0.25) : Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(50),
          onTap: () => onSelected(),
          child: ListTile(
            title: Text(
              label,
              style: theme.textTheme.bodyMedium,
            ),
            leading: icon != null ? Icon(icon) : this.leading,
            trailing: Icon(trailingIcon),
          ),
        ),
      ),
    );
  }
}
