import { View, Text, Button } from 'react-native';

export function Home() {
  return (
    <View style={{ padding: 16 }}>
      <Text>Hello</Text>
      <Button title="Go" onPress={() => {}} />
    </View>
  );
}

export const Card = ({ title }: { title: string }) => (
  <div className="card">
    <h2>{title}</h2>
  </div>
);
